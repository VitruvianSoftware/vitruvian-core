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

//! jq 1.8 total ordering (`compare`), value equality (`jq_eq`), and collection
//! primitives (`sort`, `sort_by`, `group_by`, `unique`, `unique_by`).

use std::cmp::Ordering;

use crate::value::Value;

fn type_rank(v: &Value) -> u8 {
    match v {
        Value::Null => 0,
        Value::Bool(false) => 1,
        Value::Bool(true) => 2,
        Value::Number(_) => 3,
        Value::String(_) => 4,
        Value::Array(_) => 5,
        Value::Object(_) => 6,
    }
}

fn sorted_entries(entries: &[(String, Value)]) -> Vec<(&str, &Value)> {
    let mut out: Vec<(&str, &Value)> = entries.iter().map(|(k, v)| (k.as_str(), v)).collect();
    out.sort_by(|a, b| a.0.as_bytes().cmp(b.0.as_bytes()));
    out
}

/// jq's total order: `null < false < true < numbers < strings < arrays < objects`.
/// Objects compare their sorted key lists first, then values in sorted key order.
pub fn compare(a: &Value, b: &Value) -> Ordering {
    enum Work<'a> {
        Pair(&'a Value, &'a Value),
        TieBreak(Ordering),
    }

    let mut stack = vec![Work::Pair(a, b)];
    while let Some(item) = stack.pop() {
        let (x, y) = match item {
            Work::TieBreak(ord) => {
                if ord != Ordering::Equal {
                    return ord;
                }
                continue;
            }
            Work::Pair(x, y) => (x, y),
        };
        let (rx, ry) = (type_rank(x), type_rank(y));
        if rx != ry {
            return rx.cmp(&ry);
        }
        match (x, y) {
            (Value::Number(nx), Value::Number(ny)) => {
                let ord = nx.cmp_jq(ny);
                if ord != Ordering::Equal {
                    return ord;
                }
            }
            (Value::String(sx), Value::String(sy)) => {
                let ord = sx.as_bytes().cmp(sy.as_bytes());
                if ord != Ordering::Equal {
                    return ord;
                }
            }
            (Value::Array(ax), Value::Array(ay)) => {
                let len_ord = ax.len().cmp(&ay.len());
                if len_ord != Ordering::Equal {
                    stack.push(Work::TieBreak(len_ord));
                }
                for (p, q) in ax.iter().zip(ay.iter()).rev() {
                    stack.push(Work::Pair(p, q));
                }
            }
            (Value::Object(ox), Value::Object(oy)) => {
                let kx = sorted_entries(ox);
                let ky = sorted_entries(oy);
                for ((pk, _), (qk, _)) in kx.iter().zip(ky.iter()) {
                    let ord = pk.as_bytes().cmp(qk.as_bytes());
                    if ord != Ordering::Equal {
                        return ord;
                    }
                }
                let len_ord = kx.len().cmp(&ky.len());
                if len_ord != Ordering::Equal {
                    return len_ord;
                }
                for ((_, vx), (_, vy)) in kx.into_iter().zip(ky.into_iter()).rev() {
                    stack.push(Work::Pair(vx, vy));
                }
            }
            _ => {}
        }
    }
    Ordering::Equal
}

/// jq's `==` equality: numeric value equality (`1 == 1.0`, `-0 == 0`),
/// `nan != nan`, and key-order-independent object equality.
pub fn jq_eq(a: &Value, b: &Value) -> bool {
    let mut stack = vec![(a, b)];
    while let Some((x, y)) = stack.pop() {
        match (x, y) {
            (Value::Null, Value::Null) => {}
            (Value::Bool(bx), Value::Bool(by)) if bx == by => {}
            (Value::Number(nx), Value::Number(ny)) if nx.jq_eq(ny) => {}
            (Value::String(sx), Value::String(sy)) if sx == sy => {}
            (Value::Array(ax), Value::Array(ay)) if ax.len() == ay.len() => {
                for (p, q) in ax.iter().zip(ay.iter()).rev() {
                    stack.push((p, q));
                }
            }
            (Value::Object(ox), Value::Object(oy)) if ox.len() == oy.len() => {
                for (k, vx) in ox.iter().rev() {
                    let Some((_, vy)) = oy.iter().find(|(yk, _)| yk == k) else {
                        return false;
                    };
                    stack.push((vx, vy));
                }
            }
            _ => return false,
        }
    }
    true
}

/// `sort`: stable sort according to [`compare`].
pub fn sort(items: &[Value]) -> Vec<Value> {
    let mut out = items.to_vec();
    out.sort_by(compare);
    out
}

/// `sort_by(f)`: computes keys for each element (failing on the first error)
/// and returns elements stably ordered by [`compare`] on their keys.
pub fn sort_by<F>(items: &[Value], mut key_fn: F) -> Result<Vec<Value>, String>
where
    F: FnMut(&Value) -> Result<Value, String>,
{
    let mut keyed = Vec::with_capacity(items.len());
    for item in items {
        keyed.push((key_fn(item)?, item.clone()));
    }
    keyed.sort_by(|a, b| compare(&a.0, &b.0));
    Ok(keyed.into_iter().map(|(_, v)| v).collect())
}

/// `group_by(f)`: stably sorts elements by `key_fn` and groups adjacent items
/// whose keys compare equal under [`jq_eq`] (matching jq 1.8 where `nan != nan`).
pub fn group_by<F>(items: &[Value], mut key_fn: F) -> Result<Vec<Vec<Value>>, String>
where
    F: FnMut(&Value) -> Result<Value, String>,
{
    let mut keyed = Vec::with_capacity(items.len());
    for item in items {
        keyed.push((key_fn(item)?, item.clone()));
    }
    keyed.sort_by(|a, b| compare(&a.0, &b.0));
    let mut groups: Vec<Vec<Value>> = Vec::new();
    let mut prev_key: Option<Value> = None;
    for (key, item) in keyed {
        let same = matches!(&prev_key, Some(prev) if jq_eq(prev, &key));
        if same {
            groups.last_mut().expect("non-empty group").push(item);
        } else {
            groups.push(vec![item]);
            prev_key = Some(key);
        }
    }
    Ok(groups)
}

/// `unique`: stably sorts by [`compare`] and deduplicates adjacent elements
/// that satisfy [`jq_eq`].
pub fn unique(items: &[Value]) -> Vec<Value> {
    let sorted = sort(items);
    let mut out: Vec<Value> = Vec::with_capacity(sorted.len());
    for item in sorted {
        let dup = matches!(out.last(), Some(prev) if jq_eq(prev, &item));
        if !dup {
            out.push(item);
        }
    }
    out
}

/// `unique_by(f)`: stably sorts by `key_fn` and keeps the first item of each
/// run whose keys satisfy [`jq_eq`].
pub fn unique_by<F>(items: &[Value], mut key_fn: F) -> Result<Vec<Value>, String>
where
    F: FnMut(&Value) -> Result<Value, String>,
{
    let mut keyed = Vec::with_capacity(items.len());
    for item in items {
        keyed.push((key_fn(item)?, item.clone()));
    }
    keyed.sort_by(|a, b| compare(&a.0, &b.0));
    let mut out: Vec<Value> = Vec::with_capacity(keyed.len());
    let mut prev_key: Option<Value> = None;
    for (key, item) in keyed {
        let dup = matches!(&prev_key, Some(prev) if jq_eq(prev, &key));
        if !dup {
            out.push(item);
            prev_key = Some(key);
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::value::Number;

    #[test]
    fn type_rank_and_object_key_before_value_order() {
        let ordered = [
            Value::Null,
            Value::Bool(false),
            Value::Bool(true),
            Value::Number(Number::Nan),
            Value::Number(Number::NegInf),
            Value::Number(Number::parse("-1e309").unwrap()),
            Value::int(-1),
            Value::int(0),
            Value::int(1),
            Value::Number(Number::parse("1e309").unwrap()),
            Value::Number(Number::PosInf),
            Value::str(""),
            Value::str("A"),
            Value::str("a"),
            Value::Array(vec![]),
            Value::Array(vec![Value::int(1)]),
            Value::object([]),
            Value::object([("a".into(), Value::int(1))]),
            Value::object([("a".into(), Value::int(2))]),
            Value::object([("a".into(), Value::int(1)), ("b".into(), Value::int(1))]),
            Value::object([("b".into(), Value::int(0))]),
        ];
        for pair in ordered.windows(2) {
            assert_eq!(
                compare(&pair[0], &pair[1]),
                Ordering::Less,
                "{:?} vs {:?}",
                pair[0],
                pair[1]
            );
        }
    }

    #[test]
    fn unique_and_group_by_handle_numeric_equiv_and_nan() {
        let items = vec![
            Value::Number(Number::Nan),
            Value::Number(Number::Nan),
            Value::Null,
            Value::int(1),
            Value::Number(Number::parse("1.0").unwrap()),
        ];
        let u = unique(&items);
        assert_eq!(u.len(), 4);
        assert_eq!(u[0], Value::Null);
        assert!(matches!(u[1], Value::Number(Number::Nan)));
        assert!(matches!(u[2], Value::Number(Number::Nan)));
        assert_eq!(u[3], Value::int(1));

        let g = group_by(&items, |v| Ok(v.clone())).unwrap();
        assert_eq!(g.len(), 4);
        assert_eq!(g[3].len(), 2);
    }
}
