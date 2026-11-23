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

use std::cmp::Ordering;

use crate::format::{
    compact, compact_sorted, dump_trunc, format_value, interpolate, pretty, pretty_sorted, raw,
    raw_compact, raw_sorted, tostring, OutputOptions,
};
use crate::order::{compare, group_by, jq_eq, sort, sort_by, unique, unique_by};
use crate::parse::{parse_one, parse_stream, parse_stream_str, StreamItem};
use crate::value::{Number, Value};

const DEPTH_LIMIT: usize = 10_000;
const OBJECT_LIMIT: usize = 5_000;
const DROP_OVERFLOW_DEPTH: usize = 20_000;
const STACK_SIZE_2MIB: usize = 2 * 1024 * 1024;

fn run_2mib(f: impl FnOnce() + Send + 'static) {
    let handle = std::thread::Builder::new()
        .stack_size(STACK_SIZE_2MIB)
        .spawn(f)
        .expect("spawn 2 MiB test thread");
    handle.join().expect("2 MiB test thread panicked");
}

fn make_deep_array(depth: usize, leaf: Value) -> Value {
    let mut cur = leaf;
    for _ in 0..depth {
        cur = Value::Array(vec![cur]);
    }
    cur
}

fn make_deep_object(depth: usize, key: &str, leaf: Value) -> Value {
    let mut cur = leaf;
    for _ in 0..depth {
        cur = Value::Object(vec![(key.to_string(), cur)]);
    }
    cur
}

fn nested_array_json(depth: usize, leaf: &str) -> String {
    let mut s = String::with_capacity(depth * 2 + leaf.len());
    for _ in 0..depth {
        s.push('[');
    }
    s.push_str(leaf);
    for _ in 0..depth {
        s.push(']');
    }
    s
}

fn nested_object_json(depth: usize, leaf: &str) -> String {
    let prefix = "{\"a\":";
    let mut s = String::with_capacity(depth * (prefix.len() + 1) + leaf.len());
    for _ in 0..depth {
        s.push_str(prefix);
    }
    s.push_str(leaf);
    for _ in 0..depth {
        s.push('}');
    }
    s
}

#[test]
fn depth_parse_stream() {
    run_2mib(|| {
        let ok_arr = nested_array_json(DEPTH_LIMIT, "");
        let items = parse_stream(ok_arr.as_bytes());
        assert_eq!(items.len(), 1);
        assert!(matches!(items[0], StreamItem::Value(_, 0)));

        let bad_arr = nested_array_json(DEPTH_LIMIT + 1, "");
        assert_eq!(
            parse_stream(bad_arr.as_bytes()),
            vec![StreamItem::ParseError(format!(
                "Exceeds depth limit for parsing at line 1, column {}",
                DEPTH_LIMIT + 1
            ))]
        );

        let ok_obj = nested_object_json(OBJECT_LIMIT, "1");
        let obj_items = parse_stream(ok_obj.as_bytes());
        assert_eq!(obj_items.len(), 1);
        assert!(matches!(obj_items[0], StreamItem::Value(_, 0)));

        let bad_obj = nested_object_json(OBJECT_LIMIT + 1, "1");
        assert_eq!(
            parse_stream(bad_obj.as_bytes()),
            vec![StreamItem::ParseError(format!(
                "Exceeds depth limit for parsing at line 1, column {}",
                OBJECT_LIMIT * 5 + 1
            ))]
        );
    });
}

#[test]
fn depth_parse_stream_str() {
    run_2mib(|| {
        let ok_arr = nested_array_json(DEPTH_LIMIT, "1");
        let items = parse_stream_str(&ok_arr);
        assert_eq!(items.len(), 1);
        assert!(matches!(items[0], StreamItem::Value(_, 0)));

        let bad_arr = nested_array_json(DEPTH_LIMIT + 1, "1");
        assert_eq!(
            parse_stream_str(&bad_arr),
            vec![StreamItem::ParseError(format!(
                "Exceeds depth limit for parsing at line 1, column {}",
                DEPTH_LIMIT + 1
            ))]
        );
    });
}

#[test]
fn depth_parse_one() {
    run_2mib(|| {
        let ok_arr = nested_array_json(DEPTH_LIMIT, "");
        assert!(parse_one(ok_arr.as_bytes()).is_ok());

        let bad_arr = nested_array_json(DEPTH_LIMIT + 1, "");
        assert_eq!(
            parse_one(bad_arr.as_bytes()).unwrap_err(),
            format!(
                "Exceeds depth limit for parsing at line 1, column {}",
                DEPTH_LIMIT + 1
            )
        );

        let ok_obj = nested_object_json(OBJECT_LIMIT, "1");
        assert!(parse_one(ok_obj.as_bytes()).is_ok());

        let bad_obj = nested_object_json(OBJECT_LIMIT + 1, "1");
        assert_eq!(
            parse_one(bad_obj.as_bytes()).unwrap_err(),
            format!(
                "Exceeds depth limit for parsing at line 1, column {}",
                OBJECT_LIMIT * 5 + 1
            )
        );
    });
}

#[test]
fn depth_drop() {
    run_2mib(|| {
        let arr = make_deep_array(DEPTH_LIMIT, Value::int(1));
        drop(arr);
        let obj = make_deep_object(OBJECT_LIMIT, "a", Value::int(1));
        drop(obj);
        let over = make_deep_array(DROP_OVERFLOW_DEPTH, Value::int(1));
        drop(over);
    });
}

#[test]
fn depth_clone() {
    run_2mib(|| {
        let arr = make_deep_array(DEPTH_LIMIT, Value::int(1));
        let arr2 = arr.clone();
        assert_eq!(arr2.kind(), "array");

        let obj = make_deep_object(OBJECT_LIMIT, "a", Value::int(1));
        let obj2 = obj.clone();
        assert_eq!(obj2.kind(), "object");
    });
}

#[test]
fn depth_partial_eq() {
    run_2mib(|| {
        let a1 = make_deep_array(DEPTH_LIMIT, Value::int(1));
        let a2 = make_deep_array(DEPTH_LIMIT, Value::int(1));
        let a3 = make_deep_array(DEPTH_LIMIT, Value::int(2));
        assert!(a1 == a2);
        assert!(a1 != a3);

        let o1 = make_deep_object(OBJECT_LIMIT, "a", Value::int(1));
        let o2 = make_deep_object(OBJECT_LIMIT, "a", Value::int(1));
        let o3 = make_deep_object(OBJECT_LIMIT, "a", Value::int(2));
        assert!(o1 == o2);
        assert!(o1 != o3);
    });
}

#[test]
fn depth_debug() {
    run_2mib(|| {
        let arr = make_deep_array(DEPTH_LIMIT, Value::int(1));
        let dbg = format!("{arr:?}");
        assert!(dbg.starts_with("Array([Array(["));
        assert!(dbg.ends_with(")])"));
    });
}

#[test]
fn depth_compare() {
    run_2mib(|| {
        let a1 = make_deep_array(DEPTH_LIMIT, Value::int(1));
        let a2 = make_deep_array(DEPTH_LIMIT, Value::int(2));
        let a1_dup = make_deep_array(DEPTH_LIMIT, Value::int(1));
        assert_eq!(compare(&a1, &a2), Ordering::Less);
        assert_eq!(compare(&a2, &a1), Ordering::Greater);
        assert_eq!(compare(&a1, &a1_dup), Ordering::Equal);

        let o1 = make_deep_object(OBJECT_LIMIT, "a", Value::int(1));
        let o2 = make_deep_object(OBJECT_LIMIT, "a", Value::int(2));
        assert_eq!(compare(&o1, &o2), Ordering::Less);
    });
}

#[test]
fn depth_jq_eq() {
    run_2mib(|| {
        let a1 = make_deep_array(DEPTH_LIMIT, Value::int(1));
        let a1_float = make_deep_array(DEPTH_LIMIT, Value::Number(Number::parse("1.0").unwrap()));
        let a_nan1 = make_deep_array(DEPTH_LIMIT, Value::Number(Number::Nan));
        let a_nan2 = make_deep_array(DEPTH_LIMIT, Value::Number(Number::Nan));
        assert!(jq_eq(&a1, &a1_float));
        assert!(a1.jq_eq(&a1_float));
        assert!(!jq_eq(&a_nan1, &a_nan2));

        let o1 = make_deep_object(OBJECT_LIMIT, "a", Value::int(1));
        let o1_float = make_deep_object(
            OBJECT_LIMIT,
            "a",
            Value::Number(Number::parse("1.0").unwrap()),
        );
        assert!(jq_eq(&o1, &o1_float));
    });
}

#[test]
fn depth_jq_cmp() {
    run_2mib(|| {
        let a1 = make_deep_array(DEPTH_LIMIT, Value::int(1));
        let a2 = make_deep_array(DEPTH_LIMIT, Value::int(2));
        assert_eq!(a2.jq_cmp(&a1), Ordering::Greater);
        assert_eq!(a1.jq_cmp(&a2), Ordering::Less);
    });
}

#[test]
fn depth_sort() {
    run_2mib(|| {
        let items = vec![
            make_deep_array(DEPTH_LIMIT, Value::int(2)),
            make_deep_array(DEPTH_LIMIT, Value::int(1)),
        ];
        let sorted = sort(&items);
        assert_eq!(sorted.len(), 2);
        assert_eq!(compact(&sorted[0]), nested_array_json(DEPTH_LIMIT, "1"));
        assert_eq!(compact(&sorted[1]), nested_array_json(DEPTH_LIMIT, "2"));
    });
}

#[test]
fn depth_sort_by() {
    run_2mib(|| {
        let items = vec![
            Value::object([("k".into(), make_deep_array(DEPTH_LIMIT - 1, Value::int(2)))]),
            Value::object([("k".into(), make_deep_array(DEPTH_LIMIT - 1, Value::int(1)))]),
        ];
        let sorted = sort_by(&items, |v| v.index("k")).unwrap();
        assert_eq!(sorted.len(), 2);
        assert_eq!(
            compact(&sorted[0].index("k").unwrap()),
            nested_array_json(DEPTH_LIMIT - 1, "1")
        );
    });
}

#[test]
fn depth_group_by() {
    run_2mib(|| {
        let items = vec![
            Value::object([("k".into(), make_deep_array(DEPTH_LIMIT - 1, Value::int(2)))]),
            Value::object([("k".into(), make_deep_array(DEPTH_LIMIT - 1, Value::int(1)))]),
            Value::object([(
                "k".into(),
                make_deep_array(
                    DEPTH_LIMIT - 1,
                    Value::Number(Number::parse("1.0").unwrap()),
                ),
            )]),
        ];
        let groups = group_by(&items, |v| v.index("k")).unwrap();
        assert_eq!(groups.len(), 2);
        assert_eq!(groups[0].len(), 2);
        assert_eq!(groups[1].len(), 1);
    });
}

#[test]
fn depth_unique() {
    run_2mib(|| {
        let items = vec![
            make_deep_array(DEPTH_LIMIT, Value::int(2)),
            make_deep_array(DEPTH_LIMIT, Value::int(1)),
            make_deep_array(DEPTH_LIMIT, Value::Number(Number::parse("1.0").unwrap())),
        ];
        let uniq = unique(&items);
        assert_eq!(uniq.len(), 2);
        assert_eq!(compact(&uniq[0]), nested_array_json(DEPTH_LIMIT, "1"));
        assert_eq!(compact(&uniq[1]), nested_array_json(DEPTH_LIMIT, "2"));
    });
}

#[test]
fn depth_unique_by() {
    run_2mib(|| {
        let items = vec![
            Value::object([("k".into(), make_deep_array(DEPTH_LIMIT - 1, Value::int(2)))]),
            Value::object([("k".into(), make_deep_array(DEPTH_LIMIT - 1, Value::int(1)))]),
            Value::object([(
                "k".into(),
                make_deep_array(
                    DEPTH_LIMIT - 1,
                    Value::Number(Number::parse("1.0").unwrap()),
                ),
            )]),
        ];
        let uniq = unique_by(&items, |v| v.index("k")).unwrap();
        assert_eq!(uniq.len(), 2);
    });
}

#[test]
fn depth_compact() {
    run_2mib(|| {
        let arr = make_deep_array(DEPTH_LIMIT, Value::int(1));
        assert_eq!(compact(&arr), nested_array_json(DEPTH_LIMIT, "1"));

        let obj = make_deep_object(OBJECT_LIMIT, "a", Value::int(1));
        assert_eq!(compact(&obj), nested_object_json(OBJECT_LIMIT, "1"));
    });
}

#[test]
fn depth_compact_sorted() {
    run_2mib(|| {
        let leaf = Value::object([("b".into(), Value::int(1)), ("a".into(), Value::int(2))]);
        let arr = make_deep_array(DEPTH_LIMIT - 1, leaf);
        assert_eq!(
            compact_sorted(&arr),
            nested_array_json(DEPTH_LIMIT - 1, "{\"a\":2,\"b\":1}")
        );
    });
}

#[test]
fn depth_pretty() {
    run_2mib(|| {
        let arr = make_deep_array(DEPTH_LIMIT, Value::int(1));
        let out = pretty(&arr);
        assert_eq!(out.len(), 200_040_001);
        assert!(out.starts_with("[\n  [\n"));
        assert!(out.ends_with("\n  ]\n]"));
    });
}

#[test]
fn depth_pretty_sorted() {
    run_2mib(|| {
        let leaf = Value::object([("b".into(), Value::int(1)), ("a".into(), Value::int(2))]);
        let arr = make_deep_array(DEPTH_LIMIT - 1, leaf);
        let out = pretty_sorted(&arr);
        assert!(out.starts_with("[\n  [\n"));
        assert!(out.ends_with("\n  ]\n]"));
        let mid_start = out.find("\"a\":").expect("sorted key a present");
        let b_pos = out.find("\"b\":").expect("sorted key b present");
        assert!(mid_start < b_pos);
    });
}

#[test]
fn depth_raw() {
    run_2mib(|| {
        let arr = make_deep_array(DEPTH_LIMIT, Value::int(1));
        let out = raw(&arr);
        assert_eq!(out.len(), 200_040_001);
        assert!(out.starts_with("[\n  [\n"));
    });
}

#[test]
fn depth_raw_compact() {
    run_2mib(|| {
        let arr = make_deep_array(DEPTH_LIMIT, Value::int(1));
        assert_eq!(raw_compact(&arr), nested_array_json(DEPTH_LIMIT, "1"));
    });
}

#[test]
fn depth_raw_sorted() {
    run_2mib(|| {
        let leaf = Value::object([("b".into(), Value::int(1)), ("a".into(), Value::int(2))]);
        let arr = make_deep_array(DEPTH_LIMIT - 1, leaf);
        let out = raw_sorted(&arr);
        let mid_start = out.find("\"a\":").expect("sorted key a present");
        let b_pos = out.find("\"b\":").expect("sorted key b present");
        assert!(mid_start < b_pos);
    });
}

#[test]
fn depth_tostring() {
    run_2mib(|| {
        let arr = make_deep_array(DEPTH_LIMIT, Value::int(1));
        assert_eq!(tostring(&arr), nested_array_json(DEPTH_LIMIT, "1"));
    });
}

#[test]
fn depth_interpolate() {
    run_2mib(|| {
        let arr = make_deep_array(DEPTH_LIMIT, Value::int(1));
        assert_eq!(interpolate(&arr), nested_array_json(DEPTH_LIMIT, "1"));
    });
}

#[test]
fn depth_format_value() {
    run_2mib(|| {
        let leaf = Value::object([("b".into(), Value::int(1)), ("a".into(), Value::int(2))]);
        let arr = make_deep_array(DEPTH_LIMIT - 1, leaf);
        assert_eq!(
            format_value(&arr, OutputOptions::compact()),
            nested_array_json(DEPTH_LIMIT - 1, "{\"b\":1,\"a\":2}")
        );
        assert_eq!(
            format_value(&arr, OutputOptions::sorted_compact()),
            nested_array_json(DEPTH_LIMIT - 1, "{\"a\":2,\"b\":1}")
        );
        let out = format_value(&arr, OutputOptions::pretty());
        assert!(out.starts_with("[\n  [\n"));
    });
}

#[test]
fn depth_dump_trunc() {
    run_2mib(|| {
        let arr = make_deep_array(DEPTH_LIMIT, Value::int(1));
        assert_eq!(dump_trunc(&arr), format!("{}...]", "[".repeat(25)));

        let obj = make_deep_object(OBJECT_LIMIT, "a", Value::int(1));
        assert_eq!(dump_trunc(&obj), "{\"a\":{\"a\":{\"a\":{\"a\":{\"a\":...}");
    });
}

#[test]
fn depth_value_index() {
    run_2mib(|| {
        let obj = Value::object([("a".into(), make_deep_array(DEPTH_LIMIT - 1, Value::int(1)))]);
        let extracted = obj.index("a").unwrap();
        assert_eq!(extracted.kind(), "array");

        let arr = Value::Array(vec![make_deep_array(DEPTH_LIMIT - 1, Value::int(1))]);
        assert_eq!(arr.index_num(0).unwrap().kind(), "array");
        assert_eq!(
            arr.index_number(&Number::from_i64(0)).unwrap().kind(),
            "array"
        );
    });
}

#[test]
fn depth_value_iterate() {
    run_2mib(|| {
        let arr = Value::Array(vec![make_deep_array(DEPTH_LIMIT - 1, Value::int(1))]);
        assert_eq!(arr.iterate().unwrap().len(), 1);
        assert_eq!(arr.iterate_redacted().unwrap().len(), 1);
        assert_eq!(arr.iterate_opt().len(), 1);

        let obj = Value::object([("a".into(), make_deep_array(DEPTH_LIMIT - 1, Value::int(1)))]);
        assert_eq!(obj.iterate().unwrap().len(), 1);
        assert_eq!(obj.iterate_redacted().unwrap().len(), 1);
        assert_eq!(obj.iterate_opt().len(), 1);
    });
}

#[test]
fn depth_value_del_and_set() {
    run_2mib(|| {
        let mut obj = Value::object([(
            "a".into(),
            make_deep_array(DROP_OVERFLOW_DEPTH, Value::int(1)),
        )]);
        assert!(obj.set("a", Value::int(2)));
        assert_eq!(obj.get("a"), Some(&Value::int(2)));

        let mut obj2 = Value::object([(
            "a".into(),
            make_deep_array(DROP_OVERFLOW_DEPTH, Value::int(1)),
        )]);
        obj2.del_key("a").unwrap();
        assert_eq!(obj2, Value::object([]));

        let mut arr = Value::Array(vec![make_deep_array(DROP_OVERFLOW_DEPTH, Value::int(1))]);
        arr.del_index(0).unwrap();
        assert_eq!(arr, Value::Array(vec![]));

        let dedup = Value::object([
            (
                "a".into(),
                make_deep_array(DROP_OVERFLOW_DEPTH, Value::int(1)),
            ),
            ("a".into(), Value::int(9)),
        ]);
        assert_eq!(dedup, Value::object([("a".into(), Value::int(9))]));
    });
}
