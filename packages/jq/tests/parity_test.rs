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

//! Parity test against checked-in jq 1.8.2 ground truth (`tests/parity_cases.tsv`).

use std::fs;

use vitruvian_jq::{
    each, group_by, interpolate, one, sort, sort_by, tostring, unique, unique_by, Number,
    OutputOptions, Produced, RunOptions, Value,
};

fn decode_hex(hex: &str) -> Vec<u8> {
    assert!(hex.len() % 2 == 0, "odd hex length: {hex}");
    let mut out = Vec::with_capacity(hex.len() / 2);
    for chunk in hex.as_bytes().chunks_exact(2) {
        let s = std::str::from_utf8(chunk).unwrap();
        out.push(u8::from_str_radix(s, 16).unwrap());
    }
    out
}

fn parse_opts(flags: &str) -> RunOptions {
    match flags {
        "pretty" => RunOptions::pretty(),
        "compact" => RunOptions::compact(),
        "sorted" => RunOptions::sorted(),
        "sorted_compact" => RunOptions::sorted_compact(),
        "raw" => RunOptions::raw(),
        "raw_compact" => RunOptions::raw_compact(),
        "raw_sorted" => RunOptions::raw_sorted(),
        "compact_exit" => RunOptions {
            output: OutputOptions::compact(),
            exit_status: true,
        },
        other => panic!("unknown flags: {other}"),
    }
}

fn eval_op(op: &str, v: &Value) -> Produced {
    match op {
        "id" => (vec![v.clone()], None),
        "tostring_all" => match v.iterate() {
            Ok(items) => (
                vec![Value::Array(
                    items
                        .into_iter()
                        .map(|x| Value::String(tostring(&x)))
                        .collect(),
                )],
                None,
            ),
            Err(e) => (Vec::new(), Some(e)),
        },
        "interp_kv" => (|| -> Result<Value, String> {
            // jq evaluates string interpolations from right to left.
            let b = interpolate(&v.index("b")?);
            let a = interpolate(&v.index("a")?);
            Ok(Value::String(format!("k={a} v={b}")))
        })()
        .map(|s| (vec![s], None))
        .unwrap_or_else(|e| (Vec::new(), Some(e))),
        "interp_self" => (vec![Value::String(interpolate(v))], None),
        "sort" => one(v.iterate().map(|items| Value::Array(sort(&items)))),
        "unique" => one(v.iterate().map(|items| Value::Array(unique(&items)))),
        "sort_by_k" => one(v
            .iterate()
            .and_then(|items| sort_by(&items, |x| x.index("k")))
            .map(Value::Array)),
        "group_by_k" => one(v
            .iterate()
            .and_then(|items| group_by(&items, |x| x.index("k")))
            .map(|groups| Value::Array(groups.into_iter().map(Value::Array).collect()))),
        "unique_by_k" => one(v
            .iterate()
            .and_then(|items| unique_by(&items, |x| x.index("k")))
            .map(Value::Array)),
        "idx_foo" => one(v.index("foo")),
        "idx_x" => one(v.index("x")),
        "idx_a" => one(v.index("a")),
        "idx_long27" => one(v.index(&"k".repeat(27))),
        "idx_long28" => one(v.index(&"k".repeat(28))),
        "idx_long_utf8" => one(v.index(&format!("{}ékkkk", "k".repeat(23)))),
        "idx_0" => one(v.index_num(0)),
        "idx_neg1" => one(v.index_num(-1)),
        "idx_neg4" => one(v.index_num(-4)),
        "idx_1_5" => one(v.index_number(&Number::parse("1.5").unwrap())),
        "idx_neg0_5" => one(v.index_number(&Number::parse("-0.5").unwrap())),
        "idx_huge" => {
            one(v.index_number(&Number::parse("100000000000000000000000000000").unwrap()))
        }
        "iter" => match v.iterate() {
            Ok(items) => (items, None),
            Err(e) => (Vec::new(), Some(e)),
        },
        "iter_opt" => (v.iterate_opt(), None),
        "del_a" => {
            let mut copy = v.clone();
            one(copy.del_key("a").map(|()| copy))
        }
        "del_idx0" => {
            let mut copy = v.clone();
            one(copy.del_index(0).map(|()| copy))
        }
        "del_idx1" => {
            let mut copy = v.clone();
            one(copy.del_index(1).map(|()| copy))
        }
        "del_idx_neg1" => {
            let mut copy = v.clone();
            one(copy.del_index(-1).map(|()| copy))
        }
        "del_idx99" => {
            let mut copy = v.clone();
            one(copy.del_index(99).map(|()| copy))
        }
        "iter_idx_a" => each(v.iterate(), |x| one(x.index("a"))),
        "empty_filter" => (Vec::new(), None),
        "one_else_empty" => {
            if vitruvian_jq::jq_eq(v, &Value::int(1)) {
                (vec![Value::int(1)], None)
            } else {
                (Vec::new(), None)
            }
        }
        "false_if_1_else_empty" => {
            if vitruvian_jq::jq_eq(v, &Value::int(1)) {
                (vec![Value::Bool(false)], None)
            } else {
                (Vec::new(), None)
            }
        }
        "err_num_else_empty" => {
            if v.kind() == "number" {
                one(v.index("a"))
            } else {
                (Vec::new(), None)
            }
        }
        "one_err_empty" => {
            if vitruvian_jq::jq_eq(v, &Value::int(1)) {
                (vec![Value::int(1)], None)
            } else if v.kind() == "number" {
                one(v.index("a"))
            } else {
                (Vec::new(), None)
            }
        }
        "false_err_empty" => {
            if vitruvian_jq::jq_eq(v, &Value::int(1)) {
                (vec![Value::Bool(false)], None)
            } else if v.kind() == "number" {
                one(v.index("a"))
            } else {
                (Vec::new(), None)
            }
        }
        other => panic!("unknown op: {other}"),
    }
}

#[test]
fn parity_against_jq_182_cases() {
    let path = std::env::var("PARITY_CASES").expect("PARITY_CASES env var set");
    let raw = fs::read_to_string(&path).expect("read parity_cases.tsv");
    let mut lines = raw.lines();
    let header = lines.next().expect("header line");
    assert_eq!(
        header,
        "id\top\tflags\tinput_hex\tstatus\tstdout_hex\tstderr_hex"
    );

    let mut count = 0usize;
    for line in lines {
        if line.trim().is_empty() {
            continue;
        }
        let cols: Vec<&str> = line.split('\t').collect();
        assert_eq!(cols.len(), 7, "bad row: {line}");
        let (id, op, flags) = (cols[0], cols[1], cols[2]);
        let input = decode_hex(cols[3]);
        let want_status: i32 = cols[4].parse().unwrap();
        let want_stdout = decode_hex(cols[5]);
        let want_stderr = decode_hex(cols[6]);

        let opts = parse_opts(flags);
        let got = vitruvian_jq::run(&input, opts, |v| eval_op(op, v));
        assert_eq!(
            (
                got.status,
                String::from_utf8_lossy(&got.stdout).into_owned(),
                String::from_utf8_lossy(&got.stderr).into_owned()
            ),
            (
                want_status,
                String::from_utf8_lossy(&want_stdout).into_owned(),
                String::from_utf8_lossy(&want_stderr).into_owned()
            ),
            "mismatch on case {id} (op={op}, flags={flags}, input={:?})",
            String::from_utf8_lossy(&input)
        );
        count += 1;
    }
    assert!(count >= 200, "expected >= 200 parity cases, got {count}");
}
