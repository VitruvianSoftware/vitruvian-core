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

//! A JSON reader that reads what Python's `json.loads` reads (NaN and
//! Infinity, integers of any size, the last of two equal keys winning), a
//! writer that writes what `json.dumps` writes with its defaults, and
//! Python's `==` (`py_eq`).

use crate::pystr;

#[derive(Debug)]
pub enum Value {
    Null,
    Bool(bool),
    /// An integer, kept as its text: Python's ints have no size limit.
    Int(String),
    Float(f64),
    Str(String),
    Arr(Vec<Value>),
    /// Keys in document order; a repeated key keeps its first position and
    /// its last value, as a dict built by `json.loads` does.
    Obj(Vec<(String, Value)>),
}

/// Code-point-preserving JSON value returned by [`loads_codepoints`].
///
/// Keeps Python's exact `str` code points (`Vec<u32>`), including lone
/// surrogates (`0xD800..=0xDFFF`) that Rust's UTF-8 `String` cannot hold.
///
/// This type is strictly a parse result; its [`PartialEq`] is structural
/// (matching the former derived `PartialEq`, not Python `==` — for example
/// `Int("1") != Float(1.0)`, `Int("-0") != Int("0")`, and object entries compare
/// in order), implemented iteratively alongside [`Clone`] and [`Drop`] so deep
/// values up to [`CPYTHON_312_MAX_DEPTH`] do not overflow the stack. Python-style
/// comparison (`py_eq`) and formatting (`py_repr`, `py_str`, `dumps`) live on
/// [`Value`] and in consumers that convert `CodepointValue`.
#[derive(Debug)]
pub enum CodepointValue {
    Null,
    Bool(bool),
    /// An integer, kept as its text: Python's ints have no size limit.
    Int(String),
    Float(f64),
    /// A string as Unicode code points (may contain lone surrogates `0xD800..=0xDFFF`).
    Str(Vec<u32>),
    Arr(Vec<CodepointValue>),
    /// Keys in document order; a repeated key keeps its first position and
    /// its last value, as a dict built by `json.loads` does.
    Obj(Vec<(Vec<u32>, CodepointValue)>),
}

enum NodeRef<'a, K, V> {
    Null,
    Bool(bool),
    Int(&'a str),
    Float(f64),
    Str(&'a K),
    Arr(&'a [V]),
    Obj(&'a [(K, V)]),
}

enum EqStep<'a, K, V> {
    Done(bool),
    Arr(&'a [V], &'a [V]),
    Obj(&'a [(K, V)], &'a [(K, V)]),
}

enum DropFrame<T: TreeNode> {
    Arr(std::vec::IntoIter<T>),
    Obj(std::vec::IntoIter<(T::Text, T)>),
}

trait TreeNode: Sized {
    type Text: Clone + PartialEq;
    fn as_node(&self) -> NodeRef<'_, Self::Text, Self>;
    fn eq_step<'a>(a: &'a Self, b: &'a Self) -> EqStep<'a, Self::Text, Self>;
    fn take_children(&mut self) -> Option<DropFrame<Self>>;
    fn null() -> Self;
    fn bool(b: bool) -> Self;
    fn int(s: String) -> Self;
    fn float(f: f64) -> Self;
    fn str(s: Self::Text) -> Self;
    fn arr(items: Vec<Self>) -> Self;
    fn obj(items: Vec<(Self::Text, Self)>) -> Self;
}

macro_rules! tree_eq_step {
    ($ty:ident, $a:expr, $b:expr) => {
        match ($a, $b) {
            ($ty::Null, $ty::Null) => EqStep::Done(true),
            ($ty::Bool(x), $ty::Bool(y)) => EqStep::Done(x == y),
            ($ty::Int(x), $ty::Int(y)) => EqStep::Done(x == y),
            ($ty::Float(x), $ty::Float(y)) => EqStep::Done(x == y),
            ($ty::Str(x), $ty::Str(y)) => EqStep::Done(x == y),
            ($ty::Arr(x), $ty::Arr(y)) => {
                if x.len() != y.len() {
                    EqStep::Done(false)
                } else if x.is_empty() {
                    EqStep::Done(true)
                } else {
                    EqStep::Arr(x, y)
                }
            }
            ($ty::Obj(x), $ty::Obj(y)) => {
                if x.len() != y.len() {
                    EqStep::Done(false)
                } else if x.is_empty() {
                    EqStep::Done(true)
                } else {
                    EqStep::Obj(x, y)
                }
            }
            _ => EqStep::Done(false),
        }
    };
}

impl TreeNode for Value {
    type Text = String;
    #[inline(always)]
    fn as_node(&self) -> NodeRef<'_, Self::Text, Self> {
        match self {
            Value::Null => NodeRef::Null,
            Value::Bool(b) => NodeRef::Bool(*b),
            Value::Int(s) => NodeRef::Int(s),
            Value::Float(f) => NodeRef::Float(*f),
            Value::Str(s) => NodeRef::Str(s),
            Value::Arr(items) => NodeRef::Arr(items),
            Value::Obj(items) => NodeRef::Obj(items),
        }
    }
    #[inline(always)]
    fn eq_step<'a>(a: &'a Self, b: &'a Self) -> EqStep<'a, Self::Text, Self> {
        tree_eq_step!(Value, a, b)
    }
    #[inline(always)]
    fn null() -> Self {
        Value::Null
    }
    #[inline(always)]
    fn bool(b: bool) -> Self {
        Value::Bool(b)
    }
    #[inline(always)]
    fn int(s: String) -> Self {
        Value::Int(s)
    }
    #[inline(always)]
    fn float(f: f64) -> Self {
        Value::Float(f)
    }
    #[inline(always)]
    fn str(s: Self::Text) -> Self {
        Value::Str(s)
    }
    #[inline(always)]
    fn take_children(&mut self) -> Option<DropFrame<Self>> {
        match self {
            Value::Arr(items) if !items.is_empty() => {
                Some(DropFrame::Arr(std::mem::take(items).into_iter()))
            }
            Value::Obj(items) if !items.is_empty() => {
                Some(DropFrame::Obj(std::mem::take(items).into_iter()))
            }
            _ => None,
        }
    }
    #[inline(always)]
    fn arr(items: Vec<Self>) -> Self {
        Value::Arr(items)
    }
    #[inline(always)]
    fn obj(items: Vec<(Self::Text, Self)>) -> Self {
        Value::Obj(items)
    }
}

impl TreeNode for CodepointValue {
    type Text = Vec<u32>;
    #[inline(always)]
    fn as_node(&self) -> NodeRef<'_, Self::Text, Self> {
        match self {
            CodepointValue::Null => NodeRef::Null,
            CodepointValue::Bool(b) => NodeRef::Bool(*b),
            CodepointValue::Int(s) => NodeRef::Int(s),
            CodepointValue::Float(f) => NodeRef::Float(*f),
            CodepointValue::Str(s) => NodeRef::Str(s),
            CodepointValue::Arr(items) => NodeRef::Arr(items),
            CodepointValue::Obj(items) => NodeRef::Obj(items),
        }
    }
    #[inline(always)]
    fn eq_step<'a>(a: &'a Self, b: &'a Self) -> EqStep<'a, Self::Text, Self> {
        tree_eq_step!(CodepointValue, a, b)
    }
    #[inline(always)]
    fn null() -> Self {
        CodepointValue::Null
    }
    #[inline(always)]
    fn bool(b: bool) -> Self {
        CodepointValue::Bool(b)
    }
    #[inline(always)]
    fn int(s: String) -> Self {
        CodepointValue::Int(s)
    }
    #[inline(always)]
    fn float(f: f64) -> Self {
        CodepointValue::Float(f)
    }
    #[inline(always)]
    fn str(s: Self::Text) -> Self {
        CodepointValue::Str(s)
    }
    #[inline(always)]
    fn take_children(&mut self) -> Option<DropFrame<Self>> {
        match self {
            CodepointValue::Arr(items) if !items.is_empty() => {
                Some(DropFrame::Arr(std::mem::take(items).into_iter()))
            }
            CodepointValue::Obj(items) if !items.is_empty() => {
                Some(DropFrame::Obj(std::mem::take(items).into_iter()))
            }
            _ => None,
        }
    }
    #[inline(always)]
    fn arr(items: Vec<Self>) -> Self {
        CodepointValue::Arr(items)
    }
    #[inline(always)]
    fn obj(items: Vec<(Self::Text, Self)>) -> Self {
        CodepointValue::Obj(items)
    }
}

enum CloneFrame<'a, T: TreeNode> {
    Arr {
        src: &'a [T],
        idx: usize,
        out: Vec<T>,
    },
    Obj {
        src: &'a [(T::Text, T)],
        idx: usize,
        out: Vec<(T::Text, T)>,
    },
}

#[inline]
fn try_clone_leaf<T: TreeNode>(node: &T) -> Option<T> {
    match node.as_node() {
        NodeRef::Null => Some(T::null()),
        NodeRef::Bool(b) => Some(T::bool(b)),
        NodeRef::Int(s) => Some(T::int(s.to_owned())),
        NodeRef::Float(f) => Some(T::float(f)),
        NodeRef::Str(s) => Some(T::str(s.clone())),
        NodeRef::Arr(items) if items.is_empty() => Some(T::arr(Vec::new())),
        NodeRef::Obj(items) if items.is_empty() => Some(T::obj(Vec::new())),
        _ => None,
    }
}

fn clone_tree<T: TreeNode>(root: &T) -> T {
    if let Some(v) = try_clone_leaf(root) {
        return v;
    }
    let mut stack: Vec<CloneFrame<'_, T>> = Vec::new();
    let mut cur = root;
    loop {
        let mut val = loop {
            if let Some(leaf) = try_clone_leaf(cur) {
                break leaf;
            }
            match cur.as_node() {
                NodeRef::Arr(items) => {
                    let out = Vec::with_capacity(items.len());
                    stack.push(CloneFrame::Arr {
                        src: items,
                        idx: 0,
                        out,
                    });
                    cur = &items[0];
                }
                NodeRef::Obj(items) => {
                    let out = Vec::with_capacity(items.len());
                    stack.push(CloneFrame::Obj {
                        src: items,
                        idx: 0,
                        out,
                    });
                    cur = &items[0].1;
                }
                _ => unreachable!(),
            }
        };

        loop {
            let Some(top) = stack.last_mut() else {
                return val;
            };
            match top {
                CloneFrame::Arr { src, idx, out } => {
                    out.push(val);
                    *idx += 1;
                    while *idx < src.len() {
                        if let Some(leaf) = try_clone_leaf(&src[*idx]) {
                            out.push(leaf);
                            *idx += 1;
                        } else {
                            cur = &src[*idx];
                            break;
                        }
                    }
                    if *idx < src.len() {
                        break;
                    }
                    let Some(CloneFrame::Arr { out, .. }) = stack.pop() else {
                        unreachable!()
                    };
                    val = T::arr(out);
                }
                CloneFrame::Obj { src, idx, out } => {
                    out.push((src[*idx].0.clone(), val));
                    *idx += 1;
                    while *idx < src.len() {
                        if let Some(leaf) = try_clone_leaf(&src[*idx].1) {
                            out.push((src[*idx].0.clone(), leaf));
                            *idx += 1;
                        } else {
                            cur = &src[*idx].1;
                            break;
                        }
                    }
                    if *idx < src.len() {
                        break;
                    }
                    let Some(CloneFrame::Obj { out, .. }) = stack.pop() else {
                        unreachable!()
                    };
                    val = T::obj(out);
                }
            }
        }
    }
}

enum EqWork<'a, T: TreeNode> {
    Arr(std::slice::Iter<'a, T>, std::slice::Iter<'a, T>),
    Obj(
        std::slice::Iter<'a, (T::Text, T)>,
        std::slice::Iter<'a, (T::Text, T)>,
    ),
}

#[inline]
fn eq_tree<T: TreeNode>(a: &T, b: &T) -> bool {
    let mut cur = match T::eq_step(a, b) {
        EqStep::Done(res) => return res,
        EqStep::Arr(x, y) => EqWork::Arr(x.iter(), y.iter()),
        EqStep::Obj(x, y) => EqWork::Obj(x.iter(), y.iter()),
    };
    let mut stack: Vec<EqWork<'_, T>> = Vec::new();
    loop {
        let descended: Option<EqWork<'_, T>> = match cur {
            EqWork::Arr(mut ix, mut iy) => {
                let mut child = None;
                while let (Some(x), Some(y)) = (ix.next(), iy.next()) {
                    match T::eq_step(x, y) {
                        EqStep::Done(true) => {}
                        EqStep::Done(false) => return false,
                        EqStep::Arr(cx, cy) => {
                            if ix.len() > 0 {
                                stack.push(EqWork::Arr(ix, iy));
                            }
                            child = Some(EqWork::Arr(cx.iter(), cy.iter()));
                            break;
                        }
                        EqStep::Obj(cx, cy) => {
                            if ix.len() > 0 {
                                stack.push(EqWork::Arr(ix, iy));
                            }
                            child = Some(EqWork::Obj(cx.iter(), cy.iter()));
                            break;
                        }
                    }
                }
                child
            }
            EqWork::Obj(mut ix, mut iy) => {
                let mut child = None;
                while let (Some((kx, vx)), Some((ky, vy))) = (ix.next(), iy.next()) {
                    if kx != ky {
                        return false;
                    }
                    match T::eq_step(vx, vy) {
                        EqStep::Done(true) => {}
                        EqStep::Done(false) => return false,
                        EqStep::Arr(cx, cy) => {
                            if ix.len() > 0 {
                                stack.push(EqWork::Obj(ix, iy));
                            }
                            child = Some(EqWork::Arr(cx.iter(), cy.iter()));
                            break;
                        }
                        EqStep::Obj(cx, cy) => {
                            if ix.len() > 0 {
                                stack.push(EqWork::Obj(ix, iy));
                            }
                            child = Some(EqWork::Obj(cx.iter(), cy.iter()));
                            break;
                        }
                    }
                }
                child
            }
        };
        if let Some(next) = descended {
            cur = next;
        } else if let Some(next) = stack.pop() {
            cur = next;
        } else {
            return true;
        }
    }
}

impl Clone for Value {
    fn clone(&self) -> Self {
        clone_tree(self)
    }
}

impl PartialEq for Value {
    #[inline]
    fn eq(&self, other: &Self) -> bool {
        eq_tree(self, other)
    }
}

impl Clone for CodepointValue {
    fn clone(&self) -> Self {
        clone_tree(self)
    }
}

impl PartialEq for CodepointValue {
    #[inline]
    fn eq(&self, other: &Self) -> bool {
        eq_tree(self, other)
    }
}

fn drop_tree<T: TreeNode>(root: &mut T) {
    let Some(mut cur) = root.take_children() else {
        return;
    };
    let mut stack: Vec<DropFrame<T>> = Vec::new();
    loop {
        let next_frame = match &mut cur {
            DropFrame::Arr(iter) => {
                let mut descended = None;
                while let Some(mut item) = iter.next() {
                    if let Some(child) = item.take_children() {
                        descended = Some(child);
                        break;
                    }
                }
                descended
            }
            DropFrame::Obj(iter) => {
                let mut descended = None;
                while let Some((_k, mut val)) = iter.next() {
                    if let Some(child) = val.take_children() {
                        descended = Some(child);
                        break;
                    }
                }
                descended
            }
        };
        if let Some(child) = next_frame {
            let has_more = match &cur {
                DropFrame::Arr(iter) => iter.len() > 0,
                DropFrame::Obj(iter) => iter.len() > 0,
            };
            if has_more {
                stack.push(cur);
            }
            cur = child;
        } else if let Some(parent) = stack.pop() {
            cur = parent;
        } else {
            return;
        }
    }
}

impl Drop for Value {
    #[inline]
    fn drop(&mut self) {
        if matches!(self, Value::Arr(a) if !a.is_empty())
            || matches!(self, Value::Obj(o) if !o.is_empty())
        {
            drop_tree(self);
        }
    }
}

impl Drop for CodepointValue {
    #[inline]
    fn drop(&mut self) {
        if matches!(self, CodepointValue::Arr(a) if !a.is_empty())
            || matches!(self, CodepointValue::Obj(o) if !o.is_empty())
        {
            drop_tree(self);
        }
    }
}

impl Value {
    /// Drop a [`Value`]. [`Value`]'s [`Drop`] implementation is iterative, so
    /// normal `drop(v)` is already safe for deeply nested values.
    pub fn drop_iteratively(self) {
        drop(self);
    }

    /// `d.get(key)` on an object; None for a missing key or a non-object.
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Obj(items) => items.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    /// `key in d` on an object; `false` for a missing key or a non-object.
    pub fn has(&self, key: &str) -> bool {
        self.get(key).is_some()
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Value::Bool(b) => Some(*b),
            _ => None,
        }
    }

    pub fn as_arr(&self) -> Option<&[Value]> {
        match self {
            Value::Arr(items) => Some(items),
            _ => None,
        }
    }

    pub fn as_obj(&self) -> Option<&[(String, Value)]> {
        match self {
            Value::Obj(items) => Some(items),
            _ => None,
        }
    }

    pub fn is_obj(&self) -> bool {
        matches!(self, Value::Obj(_))
    }

    pub fn is_dict(&self) -> bool {
        matches!(self, Value::Obj(_))
    }

    pub fn is_list(&self) -> bool {
        matches!(self, Value::Arr(_))
    }

    pub fn is_str(&self) -> bool {
        matches!(self, Value::Str(_))
    }

    pub fn is_bool(&self) -> bool {
        matches!(self, Value::Bool(_))
    }

    pub fn is_int(&self) -> bool {
        matches!(self, Value::Int(_))
    }

    /// `isinstance(value, (int, float)) and not isinstance(value, bool)`
    pub fn is_number(&self) -> bool {
        matches!(self, Value::Int(_) | Value::Float(_))
    }

    /// `is_number(value) and float(value).is_integer()`
    pub fn is_whole(&self) -> bool {
        match self {
            Value::Int(_) => true,
            Value::Float(f) => f.is_finite() && f.fract() == 0.0,
            _ => false,
        }
    }

    /// `value >= 0` for a number (`Int` or `Float`).
    pub fn is_non_negative(&self) -> bool {
        match self {
            Value::Int(s) => !normalize_int(s).starts_with('-'),
            Value::Float(f) => !f.is_nan() && *f >= 0.0,
            _ => false,
        }
    }

    /// `json.dumps(self, separators=(",", ":"))` (with `ensure_ascii=True`).
    pub fn dumps_compact(&self) -> String {
        dumps_with(self, &DumpOptions::compact())
    }

    /// Python truthiness.
    pub fn truthy(&self) -> bool {
        match self {
            Value::Null => false,
            Value::Bool(b) => *b,
            Value::Int(s) => s.trim_start_matches('-').chars().any(|c| c != '0'),
            Value::Float(f) => *f != 0.0,
            Value::Str(s) => !s.is_empty(),
            Value::Arr(a) => !a.is_empty(),
            Value::Obj(o) => !o.is_empty(),
        }
    }

    /// The Python type name, for error messages.
    pub fn type_name(&self) -> &'static str {
        match self {
            Value::Null => "NoneType",
            Value::Bool(_) => "bool",
            Value::Int(_) => "int",
            Value::Float(_) => "float",
            Value::Str(_) => "str",
            Value::Arr(_) => "list",
            Value::Obj(_) => "dict",
        }
    }

    /// As a float, the way arithmetic on an int, float or bool sees it.
    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Value::Bool(b) => Some(if *b { 1.0 } else { 0.0 }),
            Value::Int(s) => s.parse::<f64>().ok(),
            Value::Float(f) => Some(*f),
            _ => None,
        }
    }

    /// `str(value)`, as an f-string would format it.
    pub fn py_str(&self) -> String {
        match self {
            Value::Str(s) => s.clone(),
            other => other.py_repr(),
        }
    }

    /// `repr(value)`.
    pub fn py_repr(&self) -> String {
        let mut out = String::new();
        format_value(self, &PyReprFormat, &mut out);
        out
    }
}

fn write_normalized_int(s: &str, out: &mut String) {
    let (neg, digits) = match s.strip_prefix('-') {
        Some(d) => (true, d),
        None => (false, s),
    };
    let trimmed = digits.trim_start_matches('0');
    if trimmed.is_empty() {
        out.push('0');
    } else {
        if neg {
            out.push('-');
        }
        out.push_str(trimmed);
    }
}

pub fn normalize_int(s: &str) -> String {
    let mut out = String::new();
    write_normalized_int(s, &mut out);
    out
}

enum ObjEntries<'a> {
    Raw(&'a [(String, Value)]),
    Dedup(Vec<(&'a str, &'a Value)>),
}

impl<'a> ObjEntries<'a> {
    #[inline]
    fn len(&self) -> usize {
        match self {
            ObjEntries::Raw(items) => items.len(),
            ObjEntries::Dedup(items) => items.len(),
        }
    }

    #[inline]
    fn get(&self, idx: usize) -> (&'a str, &'a Value) {
        match self {
            ObjEntries::Raw(items) => (&items[idx].0, &items[idx].1),
            ObjEntries::Dedup(items) => items[idx],
        }
    }
}

fn obj_entries<'a>(items: &'a [(String, Value)]) -> ObjEntries<'a> {
    if items.len() <= 1 {
        return ObjEntries::Raw(items);
    }
    if items.len() <= 16 {
        let mut has_dup = false;
        'outer: for i in 1..items.len() {
            let k = items[i].0.as_str();
            for j in 0..i {
                if items[j].0 == k {
                    has_dup = true;
                    break 'outer;
                }
            }
        }
        if !has_dup {
            return ObjEntries::Raw(items);
        }
        let mut out: Vec<(&'a str, &'a Value)> = Vec::with_capacity(items.len());
        for (k, v) in items {
            if let Some(slot) = out.iter_mut().find(|(ek, _)| *ek == k.as_str()) {
                slot.1 = v;
            } else {
                out.push((k.as_str(), v));
            }
        }
        return ObjEntries::Dedup(out);
    }
    let mut seen: std::collections::HashMap<&'a str, usize> =
        std::collections::HashMap::with_capacity(items.len());
    let mut out: Vec<(&'a str, &'a Value)> = Vec::with_capacity(items.len());
    let mut has_dup = false;
    for (k, v) in items {
        let key = k.as_str();
        if let Some(&idx) = seen.get(key) {
            out[idx].1 = v;
            has_dup = true;
        } else {
            seen.insert(key, out.len());
            out.push((key, v));
        }
    }
    if has_dup {
        ObjEntries::Dedup(out)
    } else {
        ObjEntries::Raw(items)
    }
}

/// The items of an object as the dict holds them: first position, last value.
pub fn dedup(items: &[(String, Value)]) -> Vec<(String, Value)> {
    let mut out: Vec<(String, Value)> = Vec::new();
    for (k, v) in items {
        if let Some(slot) = out.iter_mut().find(|(ek, _)| ek == k) {
            slot.1 = v.clone();
        } else {
            out.push((k.clone(), v.clone()));
        }
    }
    out
}

fn py_eq_leaf(a: &Value, b: &Value) -> Option<bool> {
    use Value::*;
    match (a, b) {
        (Null, Null) => Some(true),
        (Str(x), Str(y)) => Some(x == y),
        (Float(x), Float(y)) => Some(x == y),
        (Arr(x), Arr(y)) => {
            if x.len() != y.len() {
                Some(false)
            } else if x.is_empty() {
                Some(true)
            } else {
                None
            }
        }
        (Obj(x), Obj(y)) => {
            if x.is_empty() && y.is_empty() {
                Some(true)
            } else if x.is_empty() || y.is_empty() {
                Some(false)
            } else {
                None
            }
        }
        _ => Some(match (int_text(a), int_text(b)) {
            (Some(x), Some(y)) => x == y,
            (Some(x), None) => float_is(b, &x),
            (None, Some(y)) => float_is(a, &y),
            (None, None) => false,
        }),
    }
}

/// `a == b` in Python: ints, floats and bools compare by value, exactly
/// (an int equals a float only if the float is that very integer), dicts
/// regardless of key order.
pub fn py_eq(a: &Value, b: &Value) -> bool {
    if let Some(res) = py_eq_leaf(a, b) {
        return res;
    }
    let mut stack = vec![(a, b)];
    while let Some((ca, cb)) = stack.pop() {
        match (ca, cb) {
            (Value::Arr(x), Value::Arr(y)) => {
                if x.len() != y.len() {
                    return false;
                }
                for (p, q) in x.iter().zip(y) {
                    match py_eq_leaf(p, q) {
                        Some(true) => {}
                        Some(false) => return false,
                        None => stack.push((p, q)),
                    }
                }
            }
            (Value::Obj(x), Value::Obj(y)) => {
                let ox = obj_entries(x);
                let oy = obj_entries(y);
                if ox.len() != oy.len() {
                    return false;
                }
                if oy.len() > 16 {
                    let mut map = std::collections::HashMap::with_capacity(oy.len());
                    for j in 0..oy.len() {
                        let (k, v) = oy.get(j);
                        map.insert(k, v);
                    }
                    for i in 0..ox.len() {
                        let (k, vx) = ox.get(i);
                        let Some(&vy) = map.get(k) else {
                            return false;
                        };
                        match py_eq_leaf(vx, vy) {
                            Some(true) => {}
                            Some(false) => return false,
                            None => stack.push((vx, vy)),
                        }
                    }
                } else {
                    for i in 0..ox.len() {
                        let (k, vx) = ox.get(i);
                        let mut found = None;
                        for j in 0..oy.len() {
                            let (k2, vy) = oy.get(j);
                            if k == k2 {
                                found = Some(vy);
                                break;
                            }
                        }
                        let Some(vy) = found else {
                            return false;
                        };
                        match py_eq_leaf(vx, vy) {
                            Some(true) => {}
                            Some(false) => return false,
                            None => stack.push((vx, vy)),
                        }
                    }
                }
            }
            _ => unreachable!(),
        }
    }
    true
}

/// An int or a bool as its normalized decimal text.
fn int_text(v: &Value) -> Option<String> {
    match v {
        Value::Int(s) => Some(normalize_int(s)),
        Value::Bool(b) => Some(if *b { "1" } else { "0" }.into()),
        _ => None,
    }
}

/// Is `v` a float whose exact value is the integer `n`?
fn float_is(v: &Value, n: &str) -> bool {
    match v {
        Value::Float(f) if f.is_finite() && f.fract() == 0.0 => {
            // Rust prints a float's exact decimal value.
            normalize_int(&format!("{:.0}", f)) == n
        }
        _ => false,
    }
}

/// Classification of why [`loads`], [`loads_with`], [`loads_with_limits`],
/// or [`loads_codepoints`] rejected an input.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum JsonErrorKind {
    Decode,
    Recursion,
    IntDigitLimit,
}

/// A document that does not parse. The message is in Python's words where
/// that was easy; callers that mirror a crash only rely on the class.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JsonError {
    pub msg: String,
    pub pos: usize,
    pub line: usize,
    pub col: usize,
    py_msg: String,
    py_pos: usize,
    kind: JsonErrorKind,
    recursion_msg: Option<&'static str>,
}

impl JsonError {
    /// Classification of the parse failure, for callers that raise distinct
    /// Python exception types (such as `RecursionError` vs `ValueError`).
    pub fn kind(&self) -> JsonErrorKind {
        self.kind
    }

    /// CPython 3.12's `RecursionError` message for container depth errors,
    /// matching whichever container (`array` or `object`) hit the limit;
    /// `None` for non-recursion errors.
    pub fn recursion_message(&self) -> Option<&'static str> {
        self.recursion_msg
    }

    /// Matches CPython 3.12's `json` module `str(json.JSONDecodeError)`:
    /// `"{msg}: line {line} column {col} (char {pos})"`.
    ///
    /// Known version differences vs. CPython 3.13 and later:
    /// 1. For a `\uXXXX` escape that ends at end of input, CPython 3.13 and
    ///    later say `"Unterminated string starting at"`.
    /// 2. For a trailing comma, CPython 3.13 and later say
    ///    `"Illegal trailing comma before end of array/object"`.
    ///
    /// Not an error-text difference, but worth knowing: a lone surrogate
    /// escape (`\ud800` with no low half) decodes to U+FFFD here, where
    /// CPython keeps the surrogate in the string (a Rust `String` cannot).
    /// Callers that need exact lone surrogates should use [`loads_codepoints`].
    pub fn python_str(&self) -> String {
        format!(
            "{}: line {} column {} (char {})",
            self.py_msg, self.line, self.col, self.py_pos
        )
    }
}

impl std::fmt::Display for JsonError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} (char {})", self.msg, self.pos)
    }
}

/// JSONDecodeError's line and column for a position in the document.
fn locate(codepoints: &[u32], mut e: JsonError) -> JsonError {
    let before = &codepoints[..e.py_pos.min(codepoints.len())];
    e.line = before.iter().filter(|c| **c == 0x0A).count() + 1;
    e.col = match before.iter().rposition(|c| *c == 0x0A) {
        Some(nl) => e.py_pos - nl,
        None => e.py_pos + 1,
    };
    e
}

/// CPython 3.12's default `sys.get_int_max_str_digits()`.
pub const DEFAULT_INT_MAX_STR_DIGITS: usize = 4300;

/// CPython 3.12.16 `json.loads` decodes 9,997 nested arrays or objects and
/// raises `RecursionError` at 9,998 (measured with `/opt/homebrew/bin/python3.12 -I`).
pub const CPYTHON_312_MAX_DEPTH: usize = 9997;

/// Options for [`loads_with`].
///
/// `Default` (`None`) and any `Some(n)` above [`CPYTHON_312_MAX_DEPTH`] (9,997)
/// cap nesting at [`CPYTHON_312_MAX_DEPTH`] (`JsonErrorKind::Recursion`).
/// Setting `max_depth: Some(n)` for `n <= CPYTHON_312_MAX_DEPTH` allows up to
/// `n` nested objects/arrays and fails on the `(n + 1)`-th opening `{` or `[`
/// with `"maximum recursion depth exceeded"`.
#[derive(Copy, Clone, Debug, Default, PartialEq, Eq)]
pub struct LoadOptions {
    pub max_depth: Option<usize>,
}

/// Options for [`loads_codepoints`].
///
/// `Default` caps nesting at [`CPYTHON_312_MAX_DEPTH`] (9,997) and imposes no
/// integer-digit limit; any `max_depth` above [`CPYTHON_312_MAX_DEPTH`] is
/// likewise capped at 9,997.
#[derive(Copy, Clone, Debug, Default, PartialEq, Eq)]
pub struct CodepointLoadOptions {
    pub max_depth: Option<usize>,
    pub max_int_digits: Option<usize>,
}

/// Parse JSON with Python's `json.loads` semantics, capped at
/// [`CPYTHON_312_MAX_DEPTH`] (9,997) nested containers.
pub fn loads(text: &str) -> Result<Value, JsonError> {
    loads_with(text, &LoadOptions::default())
}

/// Parse JSON with Python's `json.loads` semantics and the given
/// [`LoadOptions`] (hard-capped at [`CPYTHON_312_MAX_DEPTH`]).
pub fn loads_with(text: &str, opts: &LoadOptions) -> Result<Value, JsonError> {
    loads_with_limits(text, opts.max_depth, None)
}

/// Parse JSON with Python's `json.loads` semantics and optional nesting depth
/// (`max_depth`, hard-capped at [`CPYTHON_312_MAX_DEPTH`]) and integer literal
/// digit (`int_max_str_digits`) limits.
pub fn loads_with_limits(
    text: &str,
    max_depth: Option<usize>,
    int_max_str_digits: Option<usize>,
) -> Result<Value, JsonError> {
    let codepoints: Vec<u32> = if text.is_ascii() {
        text.bytes().map(u32::from).collect()
    } else {
        text.chars().map(|c| c as u32).collect()
    };
    parse_codepoints::<Utf8Sink>(&codepoints, max_depth, int_max_str_digits)
}

/// Parse Unicode code points with Python's `json.loads` semantics while
/// preserving lone surrogates (`0xD800..=0xDFFF`) and optionally capping
/// nesting depth (hard-capped at [`CPYTHON_312_MAX_DEPTH`]) and integer literal
/// digits.
pub fn loads_codepoints(
    codepoints: &[u32],
    opts: &CodepointLoadOptions,
) -> Result<CodepointValue, JsonError> {
    parse_codepoints::<CodepointSink>(codepoints, opts.max_depth, opts.max_int_digits)
}

trait Sink {
    type Str: Eq;
    type Val;
    fn new_str() -> Self::Str;
    fn push_cp(s: &mut Self::Str, cp: u32);
    fn push_ascii_cps(s: &mut Self::Str, cps: &[u32]);
    fn null() -> Self::Val;
    fn bool(b: bool) -> Self::Val;
    fn int(text: String) -> Self::Val;
    fn float(f: f64) -> Self::Val;
    fn str(s: Self::Str) -> Self::Val;
    fn arr(items: Vec<Self::Val>) -> Self::Val;
    fn obj(items: Vec<(Self::Str, Self::Val)>) -> Self::Val;
    fn drop_val(v: Self::Val);
}

struct Utf8Sink;

impl Sink for Utf8Sink {
    type Str = String;
    type Val = Value;

    fn new_str() -> Self::Str {
        String::new()
    }

    fn push_cp(s: &mut Self::Str, cp: u32) {
        // A lone surrogate cannot live in a Rust string.
        s.push(char::from_u32(cp).unwrap_or('\u{fffd}'));
    }

    fn push_ascii_cps(s: &mut Self::Str, cps: &[u32]) {
        s.reserve(cps.len());
        for &cp in cps {
            s.push(cp as u8 as char);
        }
    }

    fn null() -> Self::Val {
        Value::Null
    }

    fn bool(b: bool) -> Self::Val {
        Value::Bool(b)
    }

    fn int(text: String) -> Self::Val {
        Value::Int(text)
    }

    fn float(f: f64) -> Self::Val {
        Value::Float(f)
    }

    fn str(s: Self::Str) -> Self::Val {
        Value::Str(s)
    }

    fn arr(items: Vec<Self::Val>) -> Self::Val {
        Value::Arr(items)
    }

    fn obj(items: Vec<(Self::Str, Self::Val)>) -> Self::Val {
        Value::Obj(items)
    }

    fn drop_val(v: Self::Val) {
        drop(v);
    }
}

struct CodepointSink;

impl Sink for CodepointSink {
    type Str = Vec<u32>;
    type Val = CodepointValue;

    fn new_str() -> Self::Str {
        Vec::new()
    }

    fn push_cp(s: &mut Self::Str, cp: u32) {
        s.push(cp);
    }

    fn push_ascii_cps(s: &mut Self::Str, cps: &[u32]) {
        s.extend_from_slice(cps);
    }

    fn null() -> Self::Val {
        CodepointValue::Null
    }

    fn bool(b: bool) -> Self::Val {
        CodepointValue::Bool(b)
    }

    fn int(text: String) -> Self::Val {
        CodepointValue::Int(text)
    }

    fn float(f: f64) -> Self::Val {
        CodepointValue::Float(f)
    }

    fn str(s: Self::Str) -> Self::Val {
        CodepointValue::Str(s)
    }

    fn arr(items: Vec<Self::Val>) -> Self::Val {
        CodepointValue::Arr(items)
    }

    fn obj(items: Vec<(Self::Str, Self::Val)>) -> Self::Val {
        CodepointValue::Obj(items)
    }

    fn drop_val(v: Self::Val) {
        drop(v);
    }
}

fn parse_codepoints<S: Sink>(
    codepoints: &[u32],
    max_depth: Option<usize>,
    max_int_digits: Option<usize>,
) -> Result<S::Val, JsonError> {
    if codepoints.first() == Some(&0xFEFF) {
        let msg = "Unexpected UTF-8 BOM (decode using utf-8-sig)";
        return Err(locate(
            codepoints,
            JsonError {
                msg: msg.into(),
                pos: 0,
                line: 0,
                col: 0,
                py_msg: msg.into(),
                py_pos: 0,
                kind: JsonErrorKind::Decode,
                recursion_msg: None,
            },
        ));
    }
    let effective_max_depth = max_depth.unwrap_or(usize::MAX).min(CPYTHON_312_MAX_DEPTH);
    let mut p = Parser {
        s: codepoints,
        i: 0,
        max_depth: effective_max_depth,
        max_int_digits,
    };
    let parsed = (|| {
        p.ws();
        let v = p.document::<S>()?;
        p.ws();
        if p.i != codepoints.len() {
            S::drop_val(v);
            return Err(p.err("Extra data"));
        }
        Ok(v)
    })();
    parsed.map_err(|e| locate(codepoints, e))
}

enum Frame<S: Sink> {
    Arr(Vec<S::Val>),
    Obj(Vec<(S::Str, S::Val)>, S::Str),
}

struct FrameStack<S: Sink>(Vec<Frame<S>>);

impl<S: Sink> Drop for FrameStack<S> {
    fn drop(&mut self) {
        while let Some(frame) = self.0.pop() {
            match frame {
                Frame::Arr(items) => {
                    for v in items {
                        S::drop_val(v);
                    }
                }
                Frame::Obj(items, _) => {
                    for (_, v) in items {
                        S::drop_val(v);
                    }
                }
            }
        }
    }
}

fn is_ascii_digit(cp: u32) -> bool {
    (0x30..=0x39).contains(&cp)
}

struct Parser<'a> {
    s: &'a [u32],
    i: usize,
    max_depth: usize,
    max_int_digits: Option<usize>,
}

impl<'a> Parser<'a> {
    fn err(&self, msg: &str) -> JsonError {
        self.err_with_py(msg, self.i, msg, self.i)
    }

    fn err_with_py(&self, msg: &str, pos: usize, py_msg: &str, py_pos: usize) -> JsonError {
        self.err_kind(msg, pos, py_msg, py_pos, JsonErrorKind::Decode, None)
    }

    fn err_kind(
        &self,
        msg: &str,
        pos: usize,
        py_msg: &str,
        py_pos: usize,
        kind: JsonErrorKind,
        recursion_msg: Option<&'static str>,
    ) -> JsonError {
        JsonError {
            msg: msg.into(),
            pos,
            line: 0,
            col: 0,
            py_msg: py_msg.into(),
            py_pos,
            kind,
            recursion_msg,
        }
    }

    fn peek(&self) -> Option<u32> {
        self.s.get(self.i).copied()
    }

    fn ws(&mut self) {
        while matches!(self.peek(), Some(0x20 | 0x09 | 0x0A | 0x0D)) {
            self.i += 1;
        }
    }

    fn lit(&mut self, word: &str) -> bool {
        let mut j = self.i;
        for b in word.bytes() {
            if self.s.get(j) != Some(&(b as u32)) {
                return false;
            }
            j += 1;
        }
        self.i = j;
        true
    }

    fn object_key<S: Sink>(&mut self) -> Result<S::Str, JsonError> {
        if self.peek() != Some('"' as u32) {
            return Err(self.err("Expecting property name enclosed in double quotes"));
        }
        self.i += 1;
        let key = self.string::<S>()?;
        self.ws();
        if self.peek() != Some(':' as u32) {
            return Err(self.err("Expecting ':' delimiter"));
        }
        self.i += 1;
        self.ws();
        Ok(key)
    }

    fn document<S: Sink>(&mut self) -> Result<S::Val, JsonError> {
        let mut stack = FrameStack::<S>(Vec::new());
        loop {
            let mut container: Option<S::Val> = None;
            if let Some(ch) = self.peek() {
                if ch == '{' as u32 || ch == '[' as u32 {
                    let is_obj = ch == '{' as u32;
                    if stack.0.len() >= self.max_depth {
                        let recursion_msg = if is_obj {
                            "maximum recursion depth exceeded while decoding a JSON object from a unicode string"
                        } else {
                            "maximum recursion depth exceeded while decoding a JSON array from a unicode string"
                        };
                        return Err(self.err_kind(
                            "maximum recursion depth exceeded",
                            self.i,
                            "maximum recursion depth exceeded",
                            self.i,
                            JsonErrorKind::Recursion,
                            Some(recursion_msg),
                        ));
                    }
                    self.i += 1;
                    self.ws();
                    if is_obj {
                        if self.peek() == Some('}' as u32) {
                            self.i += 1;
                            container = Some(S::obj(Vec::new()));
                        } else {
                            let key = self.object_key::<S>()?;
                            stack.0.push(Frame::Obj(Vec::new(), key));
                            continue;
                        }
                    } else if self.peek() == Some(']' as u32) {
                        self.i += 1;
                        container = Some(S::arr(Vec::new()));
                    } else {
                        stack.0.push(Frame::Arr(Vec::new()));
                        continue;
                    }
                }
            }
            let mut val = match container {
                Some(v) => v,
                None => self.scalar::<S>()?,
            };
            loop {
                let Some(frame) = stack.0.last_mut() else {
                    return Ok(val);
                };
                let (close, is_arr) = match frame {
                    Frame::Arr(items) => {
                        items.push(val);
                        (']' as u32, true)
                    }
                    Frame::Obj(items, key) => {
                        let k = std::mem::replace(key, S::new_str());
                        if let Some(slot) = items.iter_mut().find(|(ek, _)| *ek == k) {
                            let old = std::mem::replace(&mut slot.1, val);
                            S::drop_val(old);
                        } else {
                            items.push((k, val));
                        }
                        ('}' as u32, false)
                    }
                };
                self.ws();
                match self.peek() {
                    Some(ch) if ch == close => {
                        self.i += 1;
                        val = match stack.0.pop().expect("frame present") {
                            Frame::Arr(items) => S::arr(items),
                            Frame::Obj(items, _) => S::obj(items),
                        };
                    }
                    Some(ch) if ch == ',' as u32 => {
                        self.i += 1;
                        self.ws();
                        if !is_arr {
                            let key = self.object_key::<S>()?;
                            if let Some(Frame::Obj(_, slot)) = stack.0.last_mut() {
                                *slot = key;
                            }
                        }
                        break;
                    }
                    _ => return Err(self.err("Expecting ',' delimiter")),
                }
            }
        }
    }

    fn scalar<S: Sink>(&mut self) -> Result<S::Val, JsonError> {
        match self.peek() {
            Some(0x22) => {
                self.i += 1;
                Ok(S::str(self.string::<S>()?))
            }
            Some(0x6E) if self.lit("null") => Ok(S::null()),
            Some(0x74) if self.lit("true") => Ok(S::bool(true)),
            Some(0x66) if self.lit("false") => Ok(S::bool(false)),
            Some(0x4E) if self.lit("NaN") => Ok(S::float(f64::NAN)),
            Some(0x49) if self.lit("Infinity") => Ok(S::float(f64::INFINITY)),
            Some(0x2D)
                if self.s.get(self.i + 1) == Some(&('I' as u32)) && self.lit("-Infinity") =>
            {
                Ok(S::float(f64::NEG_INFINITY))
            }
            Some(c) if c == '-' as u32 || is_ascii_digit(c) => self.number::<S>(),
            _ => Err(self.err("Expecting value")),
        }
    }

    fn number<S: Sink>(&mut self) -> Result<S::Val, JsonError> {
        let start = self.i;
        if self.peek() == Some('-' as u32) {
            self.i += 1;
        }
        match self.peek() {
            Some(c) if c == '0' as u32 => self.i += 1,
            Some(c) if is_ascii_digit(c) => {
                while matches!(self.peek(), Some(c) if is_ascii_digit(c)) {
                    self.i += 1;
                }
            }
            _ => {
                self.i = start;
                return Err(self.err("Expecting value"));
            }
        }
        let mut is_float = false;
        if self.peek() == Some('.' as u32)
            && matches!(self.s.get(self.i + 1), Some(&c) if is_ascii_digit(c))
        {
            is_float = true;
            self.i += 1;
            while matches!(self.peek(), Some(c) if is_ascii_digit(c)) {
                self.i += 1;
            }
        }
        if matches!(self.peek(), Some(c) if c == 'e' as u32 || c == 'E' as u32) {
            let save = self.i;
            self.i += 1;
            if matches!(self.peek(), Some(c) if c == '+' as u32 || c == '-' as u32) {
                self.i += 1;
            }
            if matches!(self.peek(), Some(c) if is_ascii_digit(c)) {
                is_float = true;
                while matches!(self.peek(), Some(c) if is_ascii_digit(c)) {
                    self.i += 1;
                }
            } else {
                self.i = save;
            }
        }
        let slice = &self.s[start..self.i];
        if is_float {
            let f = if slice.len() <= 64 {
                let mut buf = [0u8; 64];
                for (dst, &cp) in buf[..slice.len()].iter_mut().zip(slice) {
                    *dst = cp as u8;
                }
                std::str::from_utf8(&buf[..slice.len()])
                    .expect("ASCII number")
                    .parse::<f64>()
                    .unwrap_or(f64::NAN)
            } else {
                let mut text = String::with_capacity(slice.len());
                for &c in slice {
                    text.push(c as u8 as char);
                }
                text.parse::<f64>().unwrap_or(f64::NAN)
            };
            Ok(S::float(f))
        } else {
            if let Some(limit) = self.max_int_digits {
                let has_sign = slice.first() == Some(&('-' as u32));
                let digits = slice.len() - usize::from(has_sign);
                if digits > limit {
                    let msg = format!(
                        "Exceeds the limit ({} digits) for integer string conversion: value has {} digits; use sys.set_int_max_str_digits() to increase the limit",
                        limit, digits
                    );
                    return Err(self.err_kind(
                        &msg,
                        start,
                        &msg,
                        start,
                        JsonErrorKind::IntDigitLimit,
                        None,
                    ));
                }
            }
            let mut text = String::with_capacity(slice.len());
            for &c in slice {
                text.push(c as u8 as char);
            }
            Ok(S::int(text))
        }
    }

    fn hex4(&mut self) -> Result<u32, JsonError> {
        // JSONDecodeError points at the `u`, just before the digits; preserve
        // `self.i` in `pos` so `Display` matches origin/main.
        if self.i + 4 > self.s.len() {
            return Err(self.err_with_py(
                "Invalid \\uXXXX escape",
                self.i,
                "Invalid \\uXXXX escape",
                self.i - 1,
            ));
        }
        let mut cp = 0u32;
        for k in 0..4 {
            let d = char::from_u32(self.s[self.i + k])
                .and_then(|c| c.to_digit(16))
                .ok_or_else(|| {
                    self.err_with_py(
                        "Invalid \\uXXXX escape",
                        self.i,
                        "Invalid \\uXXXX escape",
                        self.i - 1,
                    )
                })?;
            cp = (cp << 4) | d;
        }
        self.i += 4;
        Ok(cp)
    }

    fn string<S: Sink>(&mut self) -> Result<S::Str, JsonError> {
        let start = self.i - 1;
        let mut out = S::new_str();
        let mut last_u_pos: Option<usize> = None;
        loop {
            let c = match self.peek() {
                None => {
                    // CPython 3.12's `_json.c` rejects a `\uXXXX` escape that ends
                    // right at EOF as `"Invalid \uXXXX escape"` at `u` (3.13+
                    // reports `"Unterminated string starting at"`). Preserve the
                    // legacy `msg`/`pos` so `Display` stays unchanged.
                    let (py_msg, py_pos) = match last_u_pos {
                        Some(u_pos) => ("Invalid \\uXXXX escape", u_pos),
                        None => ("Unterminated string starting at", start),
                    };
                    return Err(self.err_with_py(
                        "Unterminated string starting at",
                        self.i,
                        py_msg,
                        py_pos,
                    ));
                }
                Some(c) => c,
            };
            last_u_pos = None;
            self.i += 1;
            if c == '"' as u32 {
                return Ok(out);
            }
            if c == '\\' as u32 {
                let e = self.peek().ok_or_else(|| {
                    self.err_with_py(
                        "Unterminated string",
                        self.i,
                        "Unterminated string starting at",
                        start,
                    )
                })?;
                self.i += 1;
                match e {
                    0x22 => S::push_cp(&mut out, '"' as u32),
                    0x5C => S::push_cp(&mut out, '\\' as u32),
                    0x2F => S::push_cp(&mut out, '/' as u32),
                    0x62 => S::push_cp(&mut out, 0x08),
                    0x66 => S::push_cp(&mut out, 0x0C),
                    0x6E => S::push_cp(&mut out, 0x0A),
                    0x72 => S::push_cp(&mut out, 0x0D),
                    0x74 => S::push_cp(&mut out, 0x09),
                    0x75 => {
                        let mut cp = self.hex4()?;
                        if (0xD800..0xDC00).contains(&cp)
                            && self.s.get(self.i) == Some(&('\\' as u32))
                            && self.s.get(self.i + 1) == Some(&('u' as u32))
                        {
                            let save = self.i;
                            self.i += 2;
                            let lo = self.hex4()?;
                            if (0xDC00..0xE000).contains(&lo) {
                                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                            } else {
                                self.i = save;
                            }
                        }
                        last_u_pos = Some(self.i - 5);
                        S::push_cp(&mut out, cp);
                    }
                    _ => {
                        self.i -= 1;
                        return Err(self.err_with_py(
                            "Invalid \\escape",
                            self.i,
                            "Invalid \\escape",
                            self.i - 1,
                        ));
                    }
                }
            } else if c < 0x20 {
                self.i -= 1;
                return Err(self.err("Invalid control character at"));
            } else if c < 0x80 {
                let run_start = self.i - 1;
                while let Some(&next) = self.s.get(self.i) {
                    if (0x20..0x80).contains(&next) && next != '"' as u32 && next != '\\' as u32 {
                        self.i += 1;
                    } else {
                        break;
                    }
                }
                S::push_ascii_cps(&mut out, &self.s[run_start..self.i]);
            } else {
                S::push_cp(&mut out, c);
            }
        }
    }
}

/// Options for [`dumps_with`], matching CPython's
/// `json.dumps(v, indent=..., ensure_ascii=..., separators=(item_sep, key_sep))`.
///
/// When `item_sep` is `None`, CPython's default applies: `","` when `indent`
/// is `Some(_)`, and `", "` when `indent` is `None`. When `key_sep` is
/// `None`, `": "` is used.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct DumpOptions {
    pub indent: Option<usize>,
    pub ensure_ascii: bool,
    pub item_sep: Option<&'static str>,
    pub key_sep: Option<&'static str>,
}

impl Default for DumpOptions {
    fn default() -> Self {
        Self {
            indent: None,
            ensure_ascii: true,
            item_sep: None,
            key_sep: None,
        }
    }
}

impl DumpOptions {
    /// Compact JSON matching `json.dumps(v, separators=(",", ":"))`.
    pub fn compact() -> Self {
        Self {
            indent: None,
            ensure_ascii: true,
            item_sep: Some(","),
            key_sep: Some(":"),
        }
    }
}

/// `json.dumps(value)` with its defaults: ", " and ": " separators,
/// non-ASCII escaped.
pub fn dumps(v: &Value) -> String {
    dumps_with(v, &DumpOptions::default())
}

/// `json.dumps(value, indent=..., ensure_ascii=..., separators=(...))`.
pub fn dumps_with(v: &Value, opts: &DumpOptions) -> String {
    let item_sep = opts
        .item_sep
        .unwrap_or(if opts.indent.is_some() { "," } else { ", " });
    let key_sep = opts.key_sep.unwrap_or(": ");
    let mut out = String::new();
    let fmt = DumpsFormat {
        opts,
        item_sep,
        key_sep,
    };
    format_value(v, &fmt, &mut out);
    out
}

fn write_indent(out: &mut String, indent: usize, level: usize) {
    out.push('\n');
    let spaces = indent.saturating_mul(level);
    if spaces > 0 {
        out.reserve(spaces);
        for _ in 0..spaces {
            out.push(' ');
        }
    }
}

trait JsonFormat {
    fn write_scalar(&self, v: &Value, out: &mut String) -> bool;
    fn write_key(&self, k: &str, out: &mut String);
    fn item_sep(&self) -> &str;
    fn key_sep(&self) -> &str;
    fn indent(&self) -> Option<usize>;
}

struct PyReprFormat;

impl JsonFormat for PyReprFormat {
    #[inline(always)]
    fn write_scalar(&self, v: &Value, out: &mut String) -> bool {
        match v {
            Value::Null => out.push_str("None"),
            Value::Bool(true) => out.push_str("True"),
            Value::Bool(false) => out.push_str("False"),
            Value::Int(s) => write_normalized_int(s, out),
            Value::Float(f) => out.push_str(&pystr::repr_float(*f)),
            Value::Str(s) => out.push_str(&pystr::repr_str(s)),
            Value::Arr(_) | Value::Obj(_) => return false,
        }
        true
    }

    #[inline(always)]
    fn write_key(&self, k: &str, out: &mut String) {
        out.push_str(&pystr::repr_str(k));
    }

    #[inline(always)]
    fn item_sep(&self) -> &str {
        ", "
    }

    #[inline(always)]
    fn key_sep(&self) -> &str {
        ": "
    }

    #[inline(always)]
    fn indent(&self) -> Option<usize> {
        None
    }
}

struct DumpsFormat<'a> {
    opts: &'a DumpOptions,
    item_sep: &'a str,
    key_sep: &'a str,
}

impl<'a> JsonFormat for DumpsFormat<'a> {
    #[inline(always)]
    fn write_scalar(&self, v: &Value, out: &mut String) -> bool {
        match v {
            Value::Null => out.push_str("null"),
            Value::Bool(true) => out.push_str("true"),
            Value::Bool(false) => out.push_str("false"),
            Value::Int(s) => write_normalized_int(s, out),
            Value::Float(f) => {
                if f.is_nan() {
                    out.push_str("NaN");
                } else if f.is_infinite() {
                    out.push_str(if *f > 0.0 { "Infinity" } else { "-Infinity" });
                } else {
                    out.push_str(&pystr::repr_float(*f));
                }
            }
            Value::Str(s) => write_str(s, self.opts.ensure_ascii, out),
            Value::Arr(_) | Value::Obj(_) => return false,
        }
        true
    }

    #[inline(always)]
    fn write_key(&self, k: &str, out: &mut String) {
        write_str(k, self.opts.ensure_ascii, out);
    }

    #[inline(always)]
    fn item_sep(&self) -> &str {
        self.item_sep
    }

    #[inline(always)]
    fn key_sep(&self) -> &str {
        self.key_sep
    }

    #[inline(always)]
    fn indent(&self) -> Option<usize> {
        self.opts.indent
    }
}

enum FormatFrame<'a> {
    Arr { items: &'a [Value], idx: usize },
    Obj { entries: ObjEntries<'a>, idx: usize },
}

fn format_value<F: JsonFormat>(root: &Value, fmt: &F, out: &mut String) {
    if fmt.write_scalar(root, out) {
        return;
    }
    let mut stack: Vec<FormatFrame<'_>> = Vec::new();
    let mut cur = root;
    loop {
        while !fmt.write_scalar(cur, out) {
            match cur {
                Value::Arr(items) if items.is_empty() => {
                    out.push_str("[]");
                    break;
                }
                Value::Obj(items) if items.is_empty() => {
                    out.push_str("{}");
                    break;
                }
                Value::Arr(items) => {
                    out.push('[');
                    stack.push(FormatFrame::Arr { items, idx: 0 });
                    if let Some(n) = fmt.indent() {
                        write_indent(out, n, stack.len());
                    }
                    cur = &items[0];
                }
                Value::Obj(items) => {
                    out.push('{');
                    let entries = obj_entries(items);
                    let (k, v) = entries.get(0);
                    stack.push(FormatFrame::Obj { entries, idx: 0 });
                    if let Some(n) = fmt.indent() {
                        write_indent(out, n, stack.len());
                    }
                    fmt.write_key(k, out);
                    out.push_str(fmt.key_sep());
                    cur = v;
                }
                _ => unreachable!(),
            }
        }

        loop {
            let depth = stack.len();
            let Some(top) = stack.last_mut() else {
                return;
            };
            match top {
                FormatFrame::Arr { items, idx } => {
                    *idx += 1;
                    if *idx < items.len() {
                        out.push_str(fmt.item_sep());
                        if let Some(n) = fmt.indent() {
                            write_indent(out, n, depth);
                        }
                        cur = &items[*idx];
                        break;
                    }
                    stack.pop();
                    if let Some(n) = fmt.indent() {
                        write_indent(out, n, stack.len());
                    }
                    out.push(']');
                }
                FormatFrame::Obj { entries, idx } => {
                    *idx += 1;
                    if *idx < entries.len() {
                        out.push_str(fmt.item_sep());
                        if let Some(n) = fmt.indent() {
                            write_indent(out, n, depth);
                        }
                        let (k, v) = entries.get(*idx);
                        fmt.write_key(k, out);
                        out.push_str(fmt.key_sep());
                        cur = v;
                        break;
                    }
                    stack.pop();
                    if let Some(n) = fmt.indent() {
                        write_indent(out, n, stack.len());
                    }
                    out.push('}');
                }
            }
        }
    }
}

fn write_str(s: &str, ensure_ascii: bool, out: &mut String) {
    use std::fmt::Write;
    out.push('"');
    let bytes = s.as_bytes();
    let mut start = 0usize;
    let mut i = 0usize;
    while i < bytes.len() {
        let b = bytes[i];
        if b >= 0x20 && b != b'"' && b != b'\\' && (!ensure_ascii || b <= 0x7e) {
            i += 1;
            continue;
        }
        if start < i {
            out.push_str(&s[start..i]);
        }
        if b < 0x80 {
            match b {
                b'"' => out.push_str("\\\""),
                b'\\' => out.push_str("\\\\"),
                b'\n' => out.push_str("\\n"),
                b'\r' => out.push_str("\\r"),
                b'\t' => out.push_str("\\t"),
                0x08 => out.push_str("\\b"),
                0x0C => out.push_str("\\f"),
                _ => {
                    let _ = write!(out, "\\u{:04x}", b);
                }
            }
            i += 1;
            start = i;
        } else {
            let c = s[i..].chars().next().expect("valid UTF-8");
            let cp = c as u32;
            if cp >= 0x10000 {
                let v = cp - 0x10000;
                let _ = write!(
                    out,
                    "\\u{:04x}\\u{:04x}",
                    0xD800 + (v >> 10),
                    0xDC00 + (v & 0x3FF)
                );
            } else {
                let _ = write!(out, "\\u{:04x}", cp);
            }
            i += c.len_utf8();
            start = i;
        }
    }
    if start < bytes.len() {
        out.push_str(&s[start..]);
    }
    out.push('"');
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_python_extensions() {
        let v = loads(r#"{"a": NaN, "b": -Infinity, "a": 2, "n": 123456789012345678901234567890}"#)
            .unwrap();
        assert_eq!(v.get("a"), Some(&Value::Int("2".into())));
        assert_eq!(
            v.get("n").unwrap().py_repr(),
            "123456789012345678901234567890"
        );
        assert!(matches!(v.get("b"), Some(Value::Float(f)) if f.is_infinite()));
        assert!(loads("[1,]").is_err());
        assert!(loads("{} x").is_err());
        assert!(loads("").is_err());
    }

    #[test]
    fn strings_and_surrogates() {
        let v = loads(r#""\ud83d\ude00 \u00e9 \/""#).unwrap();
        assert_eq!(v, Value::Str("\u{1F600} \u{e9} /".into()));
        assert!(loads("\"a\nb\"").is_err());
    }

    #[test]
    fn repr_and_dumps() {
        let v = loads(r#"[{"message": "it's", "n": null, "t": true}, 1.0, -0]"#).unwrap();
        assert_eq!(
            v.py_repr(),
            r#"[{'message': "it's", 'n': None, 't': True}, 1.0, 0]"#
        );
        assert_eq!(
            dumps(&v),
            r#"[{"message": "it's", "n": null, "t": true}, 1.0, 0]"#
        );
        assert_eq!(
            dumps(&Value::Str("é\u{1F600}".into())),
            r#""\u00e9\ud83d\ude00""#
        );
    }

    #[test]
    fn truthiness() {
        assert!(!Value::Int("-0".into()).truthy());
        assert!(Value::Int("3".into()).truthy());
        assert!(!Value::Obj(vec![]).truthy());
        assert!(!Value::Str(String::new()).truthy());
    }

    #[test]
    fn python_equality() {
        let int = |s: &str| Value::Int(s.into());
        assert!(py_eq(&int("101"), &Value::Float(101.0)));
        assert!(py_eq(&int("1"), &Value::Bool(true)));
        assert!(py_eq(&int("0"), &Value::Bool(false)));
        assert!(py_eq(&int("-0"), &int("0")));
        assert!(!py_eq(&int("101"), &Value::Float(101.5)));
        assert!(!py_eq(&int("101"), &Value::Str("101".into())));
        assert!(!py_eq(&Value::Float(f64::NAN), &Value::Float(f64::NAN)));
        assert!(py_eq(&int("9007199254740993"), &int("9007199254740993")));
        // 2**53 + 1 is not a float; the nearest float is 2**53.
        assert!(!py_eq(
            &int("9007199254740993"),
            &Value::Float(9007199254740992.0)
        ));
        assert!(py_eq(
            &int("9007199254740992"),
            &Value::Float(9007199254740992.0)
        ));
        assert!(py_eq(&Value::Float(1e22), &int("10000000000000000000000")));
        let a = loads(r#"{"x": [1, 2.0], "y": "z"}"#).unwrap();
        let b = loads(r#"{"y": "z", "x": [1.0, 2]}"#).unwrap();
        assert!(py_eq(&a, &b));
        assert!(!py_eq(&a, &loads(r#"{"y": "z"}"#).unwrap()));
    }

    #[test]
    fn dumps_loads_round_trip() {
        let src = r#"{"z": [1, 1.0, -0.0, 1e+16, 1.5e-07], "a": "é\ud83d\ude00\t\n", "z": "last"}"#;
        let v = loads(src).unwrap();
        assert_eq!(v.py_repr(), "{'z': 'last', 'a': 'é😀\\t\\n'}");
        let dumped = dumps(&v);
        assert_eq!(dumped, r#"{"z": "last", "a": "\u00e9\ud83d\ude00\t\n"}"#);
        assert!(py_eq(&loads(&dumped).unwrap(), &v));
    }

    #[test]
    fn error_line_and_column() {
        let e1 = loads("").unwrap_err();
        assert_eq!((e1.line, e1.col, e1.pos), (1, 1, 0));
        assert_eq!(e1.to_string(), "Expecting value (char 0)");

        let e_lf = loads("[\n1,\n\"x\" 2]").unwrap_err();
        assert_eq!((e_lf.line, e_lf.col, e_lf.pos), (3, 5, 9));

        let e_crlf = loads("[\r\n1,\r\n\"x\" 2]").unwrap_err();
        assert_eq!((e_crlf.line, e_crlf.col, e_crlf.pos), (3, 5, 11));

        let e_mb = loads("[\"é\" 2]").unwrap_err();
        assert_eq!((e_mb.line, e_mb.col, e_mb.pos), (1, 6, 5));

        let e_mb_crlf = loads("[\r\n1,\r\n\"é\" 2]").unwrap_err();
        assert_eq!((e_mb_crlf.line, e_mb_crlf.col, e_mb_crlf.pos), (3, 5, 11));

        let e_astral = loads("[\"😀\" 2]").unwrap_err();
        assert_eq!((e_astral.line, e_astral.col, e_astral.pos), (1, 6, 5));

        let e_bom = loads("\u{feff}{}").unwrap_err();
        assert_eq!((e_bom.line, e_bom.col, e_bom.pos), (1, 1, 0));
        assert_eq!(
            e_bom.python_str(),
            "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)"
        );
        assert_eq!(
            e_bom.to_string(),
            "Unexpected UTF-8 BOM (decode using utf-8-sig) (char 0)"
        );
    }

    #[test]
    fn error_python_str_matches_cpython() {
        let cases = [
            // python3: json.loads("") -> Expecting value: line 1 column 1 (char 0)
            ("", "Expecting value: line 1 column 1 (char 0)"),
            // python3: json.loads("[1 2]") -> Expecting ',' delimiter: line 1 column 4 (char 3)
            ("[1 2]", "Expecting ',' delimiter: line 1 column 4 (char 3)"),
            // python3: json.loads("{") -> Expecting property name enclosed in double quotes: line 1 column 2 (char 1)
            (
                "{",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            // python3: json.loads('["abc') -> Unterminated string starting at: line 1 column 2 (char 1)
            (
                "[\"abc",
                "Unterminated string starting at: line 1 column 2 (char 1)",
            ),
            // python3: json.loads('"ab\\') -> Unterminated string starting at: line 1 column 1 (char 0)
            (
                "\"ab\\",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            // python3: json.loads("{} x") -> Extra data: line 1 column 4 (char 3)
            ("{} x", "Extra data: line 1 column 4 (char 3)"),
            // python3: json.loads('"a\nb"') -> Invalid control character at: line 1 column 3 (char 2)
            (
                "\"a\nb\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            // python3: json.loads('{"a" 1}') -> Expecting ':' delimiter: line 1 column 6 (char 5)
            (
                "{\"a\" 1}",
                "Expecting ':' delimiter: line 1 column 6 (char 5)",
            ),
            // python3: json.loads('"\\x"') -> Invalid \escape: line 1 column 2 (char 1)
            ("\"\\x\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            // python3: json.loads('"\\u12"') -> Invalid \uXXXX escape: line 1 column 3 (char 2)
            (
                "\"\\u12\"",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            // python3: json.loads('"\\ud800\\u12"') -> Invalid \uXXXX escape: line 1 column 9 (char 8)
            (
                "\"\\ud800\\u12\"",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            // python3: json.loads('{"a":\n tru}') -> Expecting value: line 2 column 2 (char 7)
            (
                "{\"a\":\n tru}",
                "Expecting value: line 2 column 2 (char 7)",
            ),
            // python3.12: json.loads('"\\u0041') -> Invalid \uXXXX escape: line 1 column 3 (char 2)
            (
                "\"\\u0041",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            // python3.12: json.loads('"ab\\u0041') -> Invalid \uXXXX escape: line 1 column 5 (char 4)
            (
                "\"ab\\u0041",
                "Invalid \\uXXXX escape: line 1 column 5 (char 4)",
            ),
            // python3.12: json.loads('"\\ud800\\u0041') -> Invalid \uXXXX escape: line 1 column 9 (char 8)
            (
                "\"\\ud800\\u0041",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            // python3.12: json.loads('"\\ud800\\udc00') -> Invalid \uXXXX escape: line 1 column 9 (char 8)
            (
                "\"\\ud800\\udc00",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            // python3.12: json.loads('"\\\\u0041') -> Unterminated string starting at: line 1 column 1 (char 0)
            (
                "\"\\\\u0041",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
        ];
        for (input, want) in cases {
            let err = loads(input).unwrap_err();
            assert_eq!(err.python_str(), want, "{input:?}");
            assert_eq!(err.to_string(), format!("{} (char {})", err.msg, err.pos));
        }
    }

    #[test]
    fn error_display_unchanged_for_existing_paths() {
        let cases = [
            (
                "\"\\x\"",
                "Invalid \\escape",
                2,
                "Invalid \\escape (char 2)",
                (1, 2),
                "Invalid \\escape: line 1 column 2 (char 1)",
            ),
            (
                "\"\\u12\"",
                "Invalid \\uXXXX escape",
                3,
                "Invalid \\uXXXX escape (char 3)",
                (1, 3),
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"\\u123g\"",
                "Invalid \\uXXXX escape",
                3,
                "Invalid \\uXXXX escape (char 3)",
                (1, 3),
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"\\ud800\\u12\"",
                "Invalid \\uXXXX escape",
                9,
                "Invalid \\uXXXX escape (char 9)",
                (1, 9),
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"ab\\",
                "Unterminated string",
                4,
                "Unterminated string (char 4)",
                (1, 1),
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            (
                "[\"abc",
                "Unterminated string starting at",
                5,
                "Unterminated string starting at (char 5)",
                (1, 2),
                "Unterminated string starting at: line 1 column 2 (char 1)",
            ),
            (
                "\"\\u0041",
                "Unterminated string starting at",
                7,
                "Unterminated string starting at (char 7)",
                (1, 3),
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"ab\\u0041",
                "Unterminated string starting at",
                9,
                "Unterminated string starting at (char 9)",
                (1, 5),
                "Invalid \\uXXXX escape: line 1 column 5 (char 4)",
            ),
            (
                "\"\\ud800\\u0041",
                "Unterminated string starting at",
                13,
                "Unterminated string starting at (char 13)",
                (1, 9),
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"\\ud800\\udc00",
                "Unterminated string starting at",
                13,
                "Unterminated string starting at (char 13)",
                (1, 9),
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
        ];
        for (input, old_msg, old_pos, old_display, (py_line, py_col), py_str) in cases {
            let err = loads(input).unwrap_err();
            assert_eq!(err.msg, old_msg, "{input:?}");
            assert_eq!(err.pos, old_pos, "{input:?}");
            assert_eq!(err.to_string(), old_display, "{input:?}");
            assert_eq!((err.line, err.col), (py_line, py_col), "{input:?}");
            assert_eq!(err.python_str(), py_str, "{input:?}");
        }
    }

    #[test]
    fn dumps_with_options() {
        let nested = loads(r#"{"a": [1, {"b": true, "c": null}], "e": {}, "f": []}"#).unwrap();
        assert_eq!(
            dumps_with(
                &nested,
                &DumpOptions {
                    indent: Some(2),
                    ..DumpOptions::default()
                }
            ),
            "{\n  \"a\": [\n    1,\n    {\n      \"b\": true,\n      \"c\": null\n    }\n  ],\n  \"e\": {},\n  \"f\": []\n}"
        );
        assert_eq!(
            dumps_with(
                &Value::Obj(vec![]),
                &DumpOptions {
                    indent: Some(2),
                    ..DumpOptions::default()
                }
            ),
            "{}"
        );
        assert_eq!(
            dumps_with(
                &Value::Arr(vec![]),
                &DumpOptions {
                    indent: Some(2),
                    ..DumpOptions::default()
                }
            ),
            "[]"
        );

        let shallow = loads(r#"{"a": [1, 2]}"#).unwrap();
        assert_eq!(
            dumps_with(
                &shallow,
                &DumpOptions {
                    indent: Some(0),
                    ..DumpOptions::default()
                }
            ),
            "{\n\"a\": [\n1,\n2\n]\n}"
        );
        assert_eq!(
            dumps_with(
                &shallow,
                &DumpOptions {
                    indent: Some(2),
                    item_sep: Some(", "),
                    key_sep: Some(": "),
                    ..DumpOptions::default()
                }
            ),
            "{\n  \"a\": [\n    1, \n    2\n  ]\n}"
        );

        let text = Value::Obj(vec![(
            "a".into(),
            Value::Str("é😀\n\u{0000}\u{007f}".into()),
        )]);
        assert_eq!(
            dumps_with(
                &text,
                &DumpOptions {
                    ensure_ascii: false,
                    ..DumpOptions::default()
                }
            ),
            "{\"a\": \"é😀\\n\\u0000\x7f\"}"
        );
        assert_eq!(
            dumps_with(
                &text,
                &DumpOptions {
                    ensure_ascii: true,
                    ..DumpOptions::default()
                }
            ),
            r#"{"a": "\u00e9\ud83d\ude00\n\u0000\u007f"}"#
        );

        let compact_val = loads(r#"{"a": [1, 2], "b": {"c": 3}}"#).unwrap();
        let want_compact = r#"{"a":[1,2],"b":{"c":3}}"#;
        assert_eq!(
            dumps_with(&compact_val, &DumpOptions::compact()),
            want_compact
        );
        assert_eq!(
            dumps_with(
                &compact_val,
                &DumpOptions {
                    indent: None,
                    ensure_ascii: true,
                    item_sep: Some(","),
                    key_sep: Some(":"),
                }
            ),
            want_compact
        );
    }

    #[test]
    fn dumps_default_unchanged() {
        let v = Value::Obj(vec![
            ("z".into(), Value::Int("-0".into())),
            (
                "a".into(),
                Value::Arr(vec![
                    Value::Null,
                    Value::Bool(true),
                    Value::Bool(false),
                    Value::Int("123456789012345678901234567890".into()),
                    Value::Float(1.0),
                    Value::Float(-0.0),
                    Value::Float(1e16),
                    Value::Float(1.5e-7),
                    Value::Float(f64::NAN),
                    Value::Float(f64::INFINITY),
                    Value::Float(f64::NEG_INFINITY),
                    Value::Str("é\u{1F600}\t\n\"\\".into()),
                    Value::Obj(vec![]),
                    Value::Arr(vec![]),
                ]),
            ),
            ("z".into(), Value::Str("last".into())),
        ]);
        let pinned = r#"{"z": "last", "a": [null, true, false, 123456789012345678901234567890, 1.0, -0.0, 1e+16, 1.5e-07, NaN, Infinity, -Infinity, "\u00e9\ud83d\ude00\t\n\"\\", {}, []]}"#;
        assert_eq!(dumps(&v), pinned);
        assert_eq!(dumps_with(&v, &DumpOptions::default()), pinned);
    }

    #[test]
    fn loads_with_max_depth_boundary_900() {
        let handle = std::thread::Builder::new()
            .stack_size(32 * 1024 * 1024)
            .spawn(|| {
                let opts = LoadOptions {
                    max_depth: Some(900),
                };
                let ok_empty = format!("{}{}", "[".repeat(900), "]".repeat(900));
                assert!(loads_with(&ok_empty, &opts).is_ok());

                let ok_scalar = format!("{}1{}", "[".repeat(900), "]".repeat(900));
                assert!(loads_with(&ok_scalar, &opts).is_ok());

                let ok_siblings = format!("{}[],{}{}", "[".repeat(899), "{}", "]".repeat(899));
                assert!(loads_with(&ok_siblings, &opts).is_ok());

                let fail_unclosed = "[".repeat(901);
                let err = loads_with(&fail_unclosed, &opts).unwrap_err();
                assert_eq!(
                    err.python_str(),
                    "maximum recursion depth exceeded: line 1 column 901 (char 900)"
                );
                assert_eq!(
                    err.to_string(),
                    "maximum recursion depth exceeded (char 900)"
                );
                assert_eq!((err.line, err.col, err.pos), (1, 901, 900));

                let fail_empty = format!("{}{}", "[".repeat(901), "]".repeat(901));
                let err_closed = loads_with(&fail_empty, &opts).unwrap_err();
                assert_eq!(
                    err_closed.python_str(),
                    "maximum recursion depth exceeded: line 1 column 901 (char 900)"
                );

                let zero_opts = LoadOptions { max_depth: Some(0) };
                assert!(loads_with("1", &zero_opts).is_ok());
                assert!(loads_with(r#""hi""#, &zero_opts).is_ok());
                assert!(loads_with("null", &zero_opts).is_ok());
                for container in ["[]", "{}"] {
                    let err_zero = loads_with(container, &zero_opts).unwrap_err();
                    assert_eq!(
                        err_zero.python_str(),
                        "maximum recursion depth exceeded: line 1 column 1 (char 0)"
                    );
                }
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn loads_with_max_depth_mixed_containers() {
        let handle = std::thread::Builder::new()
            .stack_size(32 * 1024 * 1024)
            .spawn(|| {
                fn mixed_chain(depth: usize, start_obj: bool) -> String {
                    let mut out = String::new();
                    for k in 0..depth {
                        if (k % 2 == 0) == start_obj {
                            out.push_str(r#"{"a":"#);
                        } else {
                            out.push('[');
                        }
                    }
                    out.push('0');
                    for k in (0..depth).rev() {
                        if (k % 2 == 0) == start_obj {
                            out.push('}');
                        } else {
                            out.push(']');
                        }
                    }
                    out
                }

                let opts = LoadOptions {
                    max_depth: Some(900),
                };
                for start_obj in [false, true] {
                    let ok_doc = mixed_chain(900, start_obj);
                    assert!(loads_with(&ok_doc, &opts).is_ok());

                    let fail_doc = mixed_chain(901, start_obj);
                    let err = loads_with(&fail_doc, &opts).unwrap_err();
                    assert_eq!(err.msg, "maximum recursion depth exceeded");
                }

                let err_small =
                    loads_with(r#"[{"a":{}}]"#, &LoadOptions { max_depth: Some(2) }).unwrap_err();
                assert_eq!(
                    err_small.python_str(),
                    "maximum recursion depth exceeded: line 1 column 7 (char 6)"
                );
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn loads_with_max_depth_error_line_and_column() {
        let handle = std::thread::Builder::new()
            .stack_size(32 * 1024 * 1024)
            .spawn(|| {
                let doc = format!("{}\n[", "[".repeat(900));
                let err = loads_with(
                    &doc,
                    &LoadOptions {
                        max_depth: Some(900),
                    },
                )
                .unwrap_err();
                assert_eq!(
                    err.python_str(),
                    "maximum recursion depth exceeded: line 2 column 1 (char 901)"
                );
                assert_eq!((err.line, err.col, err.pos), (2, 1, 901));

                let mb_err = loads_with("{\"é\":\n  [[]]}", &LoadOptions { max_depth: Some(2) })
                    .unwrap_err();
                assert_eq!(
                    mb_err.python_str(),
                    "maximum recursion depth exceeded: line 2 column 4 (char 9)"
                );
                assert_eq!((mb_err.line, mb_err.col, mb_err.pos), (2, 4, 9));
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn loads_default_accepts_depth_5000() {
        assert_eq!(LoadOptions::default(), LoadOptions { max_depth: None });
        // Unoptimized test threads default to a 2 MiB stack; give the recursive
        // parser and Value::drop enough stack to walk 5,000 levels.
        let handle = std::thread::Builder::new()
            .stack_size(32 * 1024 * 1024)
            .spawn(|| {
                let doc = format!("{}{}", "[".repeat(5_000), "]".repeat(5_000));
                let v = loads(&doc);
                assert!(matches!(v, Ok(Value::Arr(_))));
                drop(v);
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn existing_display_python_str_and_dumps_pinned() {
        let e1 = loads("[1 2]").unwrap_err();
        assert_eq!(e1.to_string(), "Expecting ',' delimiter (char 3)");
        assert_eq!(
            e1.python_str(),
            "Expecting ',' delimiter: line 1 column 4 (char 3)"
        );

        let e2 = loads("").unwrap_err();
        assert_eq!(e2.to_string(), "Expecting value (char 0)");
        assert_eq!(e2.python_str(), "Expecting value: line 1 column 1 (char 0)");

        let e3 = loads(r#""\x""#).unwrap_err();
        assert_eq!(e3.to_string(), "Invalid \\escape (char 2)");
        assert_eq!(
            e3.python_str(),
            "Invalid \\escape: line 1 column 2 (char 1)"
        );

        let v = loads(r#"{"b": [1, 2.0, "é"], "a": null}"#).unwrap();
        assert_eq!(dumps(&v), r#"{"b": [1, 2.0, "\u00e9"], "a": null}"#);
    }

    #[test]
    fn value_helpers_and_dumps_compact() {
        let obj = loads(r#"{"s": "hi", "b": true, "i": -0, "f": 2.0, "a": [1, 2]}"#).unwrap();
        assert!(obj.has("s"));
        assert!(!obj.has("missing"));
        assert!(!Value::Null.has("s"));
        assert!(obj.is_dict());
        assert!(!obj.is_list());
        assert_eq!(obj.as_obj().map(|items| items.len()), Some(5));
        assert_eq!(Value::Null.as_obj(), None);

        let s = obj.get("s").unwrap();
        assert!(s.is_str());
        assert_eq!(s.as_str(), Some("hi"));
        assert_eq!(obj.get("i").unwrap().as_str(), None);

        let b = obj.get("b").unwrap();
        assert!(b.is_bool());
        assert_eq!(b.as_bool(), Some(true));
        assert!(!b.is_number());
        assert!(!b.is_whole());
        assert!(!b.is_non_negative());

        let i = obj.get("i").unwrap();
        assert!(i.is_int());
        assert!(i.is_number());
        assert!(i.is_whole());
        assert!(i.is_non_negative());
        assert!(!Value::Int("-1".into()).is_non_negative());
        assert!(!Value::Int("-001".into()).is_non_negative());
        assert!(Value::Int("-000".into()).is_non_negative());

        let f = obj.get("f").unwrap();
        assert!(f.is_number());
        assert!(f.is_whole());
        assert!(f.is_non_negative());
        assert!(!Value::Float(2.5).is_whole());
        assert!(Value::Float(-0.0).is_non_negative());
        assert!(!Value::Float(-0.1).is_non_negative());
        assert!(!Value::Float(f64::NAN).is_whole());
        assert!(!Value::Float(f64::NAN).is_non_negative());
        assert!(!Value::Float(f64::INFINITY).is_whole());
        assert!(Value::Float(f64::INFINITY).is_non_negative());
        assert!(!Value::Float(f64::NEG_INFINITY).is_non_negative());

        let a = obj.get("a").unwrap();
        assert!(a.is_list());
        assert_eq!(a.as_arr().map(|items| items.len()), Some(2));
        assert_eq!(s.as_arr(), None);

        assert_eq!(normalize_int("-000"), "0");
        assert_eq!(normalize_int("-0042"), "-42");
        assert_eq!(normalize_int("0042"), "42");

        let rich = Value::Obj(vec![
            ("txt".into(), Value::Str("é😀\u{007f}\x08\x0c".into())),
            ("nan".into(), Value::Float(f64::NAN)),
            ("inf".into(), Value::Float(f64::INFINITY)),
            ("ninf".into(), Value::Float(f64::NEG_INFINITY)),
            ("neg_zero".into(), Value::Int("-0".into())),
        ]);
        assert_eq!(
            rich.dumps_compact(),
            r#"{"txt":"\u00e9\ud83d\ude00\u007f\b\f","nan":NaN,"inf":Infinity,"ninf":-Infinity,"neg_zero":0}"#
        );
    }

    fn bs(template: &str) -> String {
        const BS: char = '\\';
        assert!(
            !template.contains(BS),
            "build escapes in code with '|' instead of literal backslashes: {template:?}"
        );
        template.replace('|', &BS.to_string())
    }

    fn read_golden_fixture() -> Option<String> {
        let mut candidates = vec![
            std::path::PathBuf::from(
                "packages/pycompat/vitruvian-pycompat/testdata/json_golden.jsonl",
            ),
            std::path::PathBuf::from("testdata/json_golden.jsonl"),
        ];
        if let Ok(dir) = std::env::var("CARGO_MANIFEST_DIR") {
            candidates.push(std::path::Path::new(&dir).join("testdata/json_golden.jsonl"));
        }
        for path in &candidates {
            if let Ok(text) = std::fs::read_to_string(path) {
                return Some(text);
            }
        }
        if std::env::var_os("TEST_SRCDIR").is_some() || std::env::var_os("TEST_WORKSPACE").is_some()
        {
            panic!("could not locate testdata/json_golden.jsonl in {candidates:?}");
        }
        eprintln!(
            "skipping golden_fixture_matches_origin_main: testdata/json_golden.jsonl is monorepo-only and absent in mirror export"
        );
        None
    }

    fn decode_hex_utf8(hex: &str) -> String {
        assert_eq!(hex.len() % 2, 0, "odd hex length");
        let bytes: Vec<u8> = (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).expect("valid hex"))
            .collect();
        String::from_utf8(bytes).expect("valid UTF-8")
    }

    fn field_str<'a>(obj: &'a Value, key: &str) -> &'a str {
        match obj.get(key) {
            Some(Value::Str(s)) => s.as_str(),
            other => panic!("expected string field {key:?}, got {other:?}"),
        }
    }

    fn field_bool(obj: &Value, key: &str) -> bool {
        match obj.get(key) {
            Some(Value::Bool(b)) => *b,
            other => panic!("expected bool field {key:?}, got {other:?}"),
        }
    }

    fn field_usize(obj: &Value, key: &str) -> usize {
        match obj.get(key) {
            Some(Value::Int(s)) => s.parse::<usize>().expect("valid usize"),
            other => panic!("expected int field {key:?}, got {other:?}"),
        }
    }

    #[test]
    fn golden_fixture_matches_origin_main() {
        let Some(content) = read_golden_fixture() else {
            return;
        };
        let mut total = 0usize;
        let mut valid = 0usize;
        let mut malformed = 0usize;

        for (idx, line) in content.lines().enumerate() {
            if line.trim().is_empty() {
                continue;
            }
            let row = loads(line).unwrap_or_else(|e| panic!("line {}: {e}", idx + 1));
            let hex = field_str(&row, "hex");
            let input = decode_hex_utf8(hex);
            let ok = field_bool(&row, "ok");
            total += 1;

            let cps: Vec<u32> = input.chars().map(|c| c as u32).collect();
            if ok {
                valid += 1;
                let want_dumps = field_str(&row, "dumps");
                let want_repr = field_str(&row, "py_repr");
                let v = loads(&input).unwrap_or_else(|e| {
                    panic!("case #{total} expected Ok on {input:?}, got Err({e:?})")
                });
                assert_eq!(dumps(&v), want_dumps, "dumps mismatch on case #{total}");
                assert_eq!(v.py_repr(), want_repr, "py_repr mismatch on case #{total}");
                assert!(
                    loads_codepoints(&cps, &CodepointLoadOptions::default()).is_ok(),
                    "loads_codepoints expected Ok on case #{total}"
                );
            } else {
                malformed += 1;
                let want_kind = match field_str(&row, "kind") {
                    "Decode" => JsonErrorKind::Decode,
                    "Recursion" => JsonErrorKind::Recursion,
                    "IntDigitLimit" => JsonErrorKind::IntDigitLimit,
                    other => panic!("unexpected kind {other:?}"),
                };
                let want_py_str = field_str(&row, "python_str");
                let want_line = field_usize(&row, "line");
                let want_col = field_usize(&row, "col");
                let want_pos = field_usize(&row, "pos");

                let err = loads(&input).unwrap_err();
                assert_eq!(err.kind(), want_kind, "kind mismatch on case #{total}");
                assert_eq!(
                    err.python_str(),
                    want_py_str,
                    "python_str mismatch on case #{total}"
                );
                assert_eq!(err.line, want_line, "line mismatch on case #{total}");
                assert_eq!(err.col, want_col, "col mismatch on case #{total}");
                assert_eq!(err.pos, want_pos, "pos mismatch on case #{total}");

                let cp_err = loads_codepoints(&cps, &CodepointLoadOptions::default()).unwrap_err();
                assert_eq!(cp_err.kind(), want_kind, "cp kind on case #{total}");
                assert_eq!(
                    cp_err.python_str(),
                    want_py_str,
                    "cp python_str on case #{total}"
                );
                assert_eq!(
                    (cp_err.line, cp_err.col, cp_err.pos),
                    (want_line, want_col, want_pos),
                    "cp loc on case #{total}"
                );
            }
        }

        assert_eq!(total, 2000);
        assert_eq!(valid, 1043);
        assert_eq!(malformed, 957);
    }

    #[test]
    fn depth_9997_all_ops_safe_on_2mib_thread() {
        const D: usize = CPYTHON_312_MAX_DEPTH;
        const SMALL: usize = 3;

        let run_2mib = |name: &'static str, f: fn()| {
            let h = std::thread::Builder::new()
                .name(name.into())
                .stack_size(2 * 1024 * 1024)
                .spawn(f)
                .unwrap();
            h.join()
                .unwrap_or_else(|e| panic!("{name} panicked: {e:?}"));
        };

        run_2mib("val_arr_9997", || {
            let small_doc = format!("{}1{}", "[".repeat(SMALL), "]".repeat(SMALL));
            let small_v = loads(&small_doc).unwrap();
            let small_diff =
                loads(&format!("{}2{}", "[".repeat(SMALL), "]".repeat(SMALL))).unwrap();
            let small_float =
                loads(&format!("{}1.0{}", "[".repeat(SMALL), "]".repeat(SMALL))).unwrap();

            let doc = format!("{}1{}", "[".repeat(D), "]".repeat(D));
            let doc_diff = format!("{}2{}", "[".repeat(D), "]".repeat(D));
            let doc_float = format!("{}1.0{}", "[".repeat(D), "]".repeat(D));

            let v = loads(&doc).unwrap();
            let v_default = loads_with(&doc, &LoadOptions::default()).unwrap();
            let v_capped = loads_with(
                &doc,
                &LoadOptions {
                    max_depth: Some(200_000),
                },
            )
            .unwrap();
            let v_diff = loads(&doc_diff).unwrap();
            let v_float = loads(&doc_float).unwrap();

            let cloned = v.clone();
            assert_eq!(v == cloned, small_v == small_v.clone());
            assert_eq!(v == v_default, true);
            assert_eq!(v == v_capped, true);
            assert_eq!(v == v_diff, small_v == small_diff);
            assert_eq!(py_eq(&v, &cloned), py_eq(&small_v, &small_v));
            assert_eq!(py_eq(&v, &v_float), py_eq(&small_v, &small_float));
            assert_eq!(py_eq(&v, &v_diff), py_eq(&small_v, &small_diff));

            let small_repr = small_v.py_repr();
            assert_eq!(small_repr, "[[[1]]]");
            assert_eq!(v.py_repr(), doc);
            assert_eq!(v.py_str(), doc);
            assert_eq!(dumps(&small_v), small_doc);
            assert_eq!(dumps(&v), doc);
            assert_eq!(dumps_with(&small_v, &DumpOptions::compact()), small_doc);
            assert_eq!(dumps_with(&v, &DumpOptions::compact()), doc);

            let indent0 = DumpOptions {
                indent: Some(0),
                ..DumpOptions::default()
            };
            assert_eq!(dumps_with(&small_v, &indent0), "[\n[\n[\n1\n]\n]\n]");
            let want_indent0 = format!("{}1{}", "[\n".repeat(D), "\n]".repeat(D));
            assert_eq!(dumps_with(&v, &indent0), want_indent0);

            drop(cloned);
            drop(v_float);
            drop(v_diff);
            drop(v_capped);
            drop(v_default);
            drop(v);
        });

        run_2mib("val_obj_9997", || {
            let small_doc = format!("{}1{}", "{\"a\":".repeat(SMALL), "}".repeat(SMALL));
            let small_v = loads(&small_doc).unwrap();
            let small_diff = loads(&format!(
                "{}2{}",
                "{\"a\":".repeat(SMALL),
                "}".repeat(SMALL)
            ))
            .unwrap();
            let small_float = loads(&format!(
                "{}1.0{}",
                "{\"a\":".repeat(SMALL),
                "}".repeat(SMALL)
            ))
            .unwrap();

            let doc = format!("{}1{}", "{\"a\":".repeat(D), "}".repeat(D));
            let doc_diff = format!("{}2{}", "{\"a\":".repeat(D), "}".repeat(D));
            let doc_float = format!("{}1.0{}", "{\"a\":".repeat(D), "}".repeat(D));

            let v = loads(&doc).unwrap();
            let v_default = loads_with(&doc, &LoadOptions::default()).unwrap();
            let v_capped = loads_with(
                &doc,
                &LoadOptions {
                    max_depth: Some(200_000),
                },
            )
            .unwrap();
            let v_diff = loads(&doc_diff).unwrap();
            let v_float = loads(&doc_float).unwrap();

            let cloned = v.clone();
            assert_eq!(v == cloned, small_v == small_v.clone());
            assert_eq!(v == v_default, true);
            assert_eq!(v == v_capped, true);
            assert_eq!(v == v_diff, small_v == small_diff);
            assert_eq!(py_eq(&v, &cloned), py_eq(&small_v, &small_v));
            assert_eq!(py_eq(&v, &v_float), py_eq(&small_v, &small_float));
            assert_eq!(py_eq(&v, &v_diff), py_eq(&small_v, &small_diff));

            assert_eq!(small_v.py_repr(), "{'a': {'a': {'a': 1}}}");
            let want_repr = format!("{}1{}", "{'a': ".repeat(D), "}".repeat(D));
            assert_eq!(v.py_repr(), want_repr);
            assert_eq!(v.py_str(), want_repr);
            assert_eq!(dumps(&small_v), r#"{"a": {"a": {"a": 1}}}"#);
            let want_dumps = format!("{}1{}", "{\"a\": ".repeat(D), "}".repeat(D));
            assert_eq!(dumps(&v), want_dumps);
            assert_eq!(dumps_with(&small_v, &DumpOptions::compact()), small_doc);
            assert_eq!(dumps_with(&v, &DumpOptions::compact()), doc);

            let indent0 = DumpOptions {
                indent: Some(0),
                ..DumpOptions::default()
            };
            assert_eq!(
                dumps_with(&small_v, &indent0),
                "{\n\"a\": {\n\"a\": {\n\"a\": 1\n}\n}\n}"
            );
            let want_indent0 = format!("{}1{}", "{\n\"a\": ".repeat(D), "\n}".repeat(D));
            assert_eq!(dumps_with(&v, &indent0), want_indent0);

            drop(cloned);
            drop(v_float);
            drop(v_diff);
            drop(v_capped);
            drop(v_default);
            drop(v);
        });

        run_2mib("cp_arr_9997", || {
            let to_cps = |s: &str| -> Vec<u32> { s.chars().map(|c| c as u32).collect() };
            let small = loads_codepoints(
                &to_cps(&format!("{}1{}", "[".repeat(SMALL), "]".repeat(SMALL))),
                &CodepointLoadOptions::default(),
            )
            .unwrap();
            let small_diff = loads_codepoints(
                &to_cps(&format!("{}2{}", "[".repeat(SMALL), "]".repeat(SMALL))),
                &CodepointLoadOptions::default(),
            )
            .unwrap();

            let cps = to_cps(&format!("{}1{}", "[".repeat(D), "]".repeat(D)));
            let cps_diff = to_cps(&format!("{}2{}", "[".repeat(D), "]".repeat(D)));

            let cp = loads_codepoints(&cps, &CodepointLoadOptions::default()).unwrap();
            let cp_capped = loads_codepoints(
                &cps,
                &CodepointLoadOptions {
                    max_depth: Some(200_000),
                    max_int_digits: None,
                },
            )
            .unwrap();
            let cp_diff = loads_codepoints(&cps_diff, &CodepointLoadOptions::default()).unwrap();
            let cloned = cp.clone();
            assert_eq!(cp == cloned, small == small.clone());
            assert_eq!(cp == cp_capped, true);
            assert_eq!(cp == cp_diff, small == small_diff);
            drop(cloned);
            drop(cp_diff);
            drop(cp_capped);
            drop(cp);
        });

        run_2mib("cp_obj_9997", || {
            let to_cps = |s: &str| -> Vec<u32> { s.chars().map(|c| c as u32).collect() };
            let small = loads_codepoints(
                &to_cps(&format!(
                    "{}1{}",
                    "{\"a\":".repeat(SMALL),
                    "}".repeat(SMALL)
                )),
                &CodepointLoadOptions::default(),
            )
            .unwrap();
            let small_diff = loads_codepoints(
                &to_cps(&format!(
                    "{}2{}",
                    "{\"a\":".repeat(SMALL),
                    "}".repeat(SMALL)
                )),
                &CodepointLoadOptions::default(),
            )
            .unwrap();

            let cps = to_cps(&format!("{}1{}", "{\"a\":".repeat(D), "}".repeat(D)));
            let cps_diff = to_cps(&format!("{}2{}", "{\"a\":".repeat(D), "}".repeat(D)));

            let cp = loads_codepoints(&cps, &CodepointLoadOptions::default()).unwrap();
            let cp_capped = loads_codepoints(
                &cps,
                &CodepointLoadOptions {
                    max_depth: Some(200_000),
                    max_int_digits: None,
                },
            )
            .unwrap();
            let cp_diff = loads_codepoints(&cps_diff, &CodepointLoadOptions::default()).unwrap();
            let cloned = cp.clone();
            assert_eq!(cp == cloned, small == small.clone());
            assert_eq!(cp == cp_capped, true);
            assert_eq!(cp == cp_diff, small == small_diff);
            drop(cloned);
            drop(cp_diff);
            drop(cp_capped);
            drop(cp);
        });
    }

    #[test]
    fn depth_9998_rejected_on_all_paths_on_2mib_thread() {
        let h = std::thread::Builder::new()
            .stack_size(2 * 1024 * 1024)
            .spawn(|| {
                let over_arr_msg = Some(
                    "maximum recursion depth exceeded while decoding a JSON array from a unicode string",
                );
                let over_obj_msg = Some(
                    "maximum recursion depth exceeded while decoding a JSON object from a unicode string",
                );

                for depth in [CPYTHON_312_MAX_DEPTH + 1, 200_000] {
                    let arr_doc = format!("{}1{}", "[".repeat(depth), "]".repeat(depth));
                    let obj_doc = format!("{}1{}", "{\"a\":".repeat(depth), "}".repeat(depth));
                    let arr_cps: Vec<u32> = arr_doc.chars().map(|c| c as u32).collect();
                    let obj_cps: Vec<u32> = obj_doc.chars().map(|c| c as u32).collect();

                    for err in [
                        loads(&arr_doc).unwrap_err(),
                        loads_with(&arr_doc, &LoadOptions::default()).unwrap_err(),
                        loads_with(
                            &arr_doc,
                            &LoadOptions {
                                max_depth: Some(CPYTHON_312_MAX_DEPTH),
                            },
                        )
                        .unwrap_err(),
                        loads_with(
                            &arr_doc,
                            &LoadOptions {
                                max_depth: Some(200_000),
                            },
                        )
                        .unwrap_err(),
                        loads_with_limits(&arr_doc, None, None).unwrap_err(),
                        loads_with_limits(&arr_doc, Some(200_000), None).unwrap_err(),
                        loads_codepoints(&arr_cps, &CodepointLoadOptions::default()).unwrap_err(),
                        loads_codepoints(
                            &arr_cps,
                            &CodepointLoadOptions {
                                max_depth: Some(200_000),
                                max_int_digits: None,
                            },
                        )
                        .unwrap_err(),
                    ] {
                        assert_eq!(err.kind(), JsonErrorKind::Recursion);
                        assert_eq!(err.recursion_message(), over_arr_msg);
                        assert_eq!(err.msg, "maximum recursion depth exceeded");
                        assert_eq!(err.pos, CPYTHON_312_MAX_DEPTH);
                    }

                    for err in [
                        loads(&obj_doc).unwrap_err(),
                        loads_with(&obj_doc, &LoadOptions::default()).unwrap_err(),
                        loads_with(
                            &obj_doc,
                            &LoadOptions {
                                max_depth: Some(CPYTHON_312_MAX_DEPTH),
                            },
                        )
                        .unwrap_err(),
                        loads_with(
                            &obj_doc,
                            &LoadOptions {
                                max_depth: Some(200_000),
                            },
                        )
                        .unwrap_err(),
                        loads_with_limits(&obj_doc, None, None).unwrap_err(),
                        loads_with_limits(&obj_doc, Some(200_000), None).unwrap_err(),
                        loads_codepoints(&obj_cps, &CodepointLoadOptions::default()).unwrap_err(),
                        loads_codepoints(
                            &obj_cps,
                            &CodepointLoadOptions {
                                max_depth: Some(200_000),
                                max_int_digits: None,
                            },
                        )
                        .unwrap_err(),
                    ] {
                        assert_eq!(err.kind(), JsonErrorKind::Recursion);
                        assert_eq!(err.recursion_message(), over_obj_msg);
                        assert_eq!(err.msg, "maximum recursion depth exceeded");
                        assert_eq!(err.pos, CPYTHON_312_MAX_DEPTH * 5);
                    }
                }
            })
            .unwrap();
        h.join().unwrap();
    }

    #[test]
    fn loads_with_limits_cpython_312_depth_boundary() {
        // Run directly on the normal default test thread (no 32 MiB stack thread needed);
        // the iterative parser handles 9,997 levels without call-stack recursion, and
        // accepted Values are freed iteratively.
        let arr_ok = format!(
            "{}{}",
            "[".repeat(CPYTHON_312_MAX_DEPTH),
            "]".repeat(CPYTHON_312_MAX_DEPTH)
        );
        let parsed_arr = loads_with_limits(&arr_ok, Some(CPYTHON_312_MAX_DEPTH), None).unwrap();
        parsed_arr.drop_iteratively();

        let arr_scalar_ok = format!(
            "{}1{}",
            "[".repeat(CPYTHON_312_MAX_DEPTH),
            "]".repeat(CPYTHON_312_MAX_DEPTH)
        );
        loads_with_limits(&arr_scalar_ok, Some(CPYTHON_312_MAX_DEPTH), None)
            .unwrap()
            .drop_iteratively();

        let arr_fail = format!(
            "{}{}",
            "[".repeat(CPYTHON_312_MAX_DEPTH + 1),
            "]".repeat(CPYTHON_312_MAX_DEPTH + 1)
        );
        let err_arr = match loads_with_limits(&arr_fail, Some(CPYTHON_312_MAX_DEPTH), None) {
            Err(e) => e,
            Ok(v) => {
                v.drop_iteratively();
                panic!("expected array recursion error at depth 9998");
            }
        };
        assert_eq!(err_arr.kind(), JsonErrorKind::Recursion);
        assert_eq!(
            err_arr.recursion_message(),
            Some("maximum recursion depth exceeded while decoding a JSON array from a unicode string")
        );
        assert_eq!(err_arr.msg, "maximum recursion depth exceeded");
        assert_eq!(err_arr.pos, CPYTHON_312_MAX_DEPTH);

        let obj_ok = format!(
            "{}1{}",
            "{\"a\":".repeat(CPYTHON_312_MAX_DEPTH),
            "}".repeat(CPYTHON_312_MAX_DEPTH)
        );
        let parsed_obj = loads_with_limits(&obj_ok, Some(CPYTHON_312_MAX_DEPTH), None).unwrap();
        parsed_obj.drop_iteratively();

        let obj_fail = format!(
            "{}1{}",
            "{\"a\":".repeat(CPYTHON_312_MAX_DEPTH + 1),
            "}".repeat(CPYTHON_312_MAX_DEPTH + 1)
        );
        let err_obj = match loads_with_limits(&obj_fail, Some(CPYTHON_312_MAX_DEPTH), None) {
            Err(e) => e,
            Ok(v) => {
                v.drop_iteratively();
                panic!("expected object recursion error at depth 9998");
            }
        };
        assert_eq!(err_obj.kind(), JsonErrorKind::Recursion);
        assert_eq!(
            err_obj.recursion_message(),
            Some("maximum recursion depth exceeded while decoding a JSON object from a unicode string")
        );
        assert_eq!(err_obj.msg, "maximum recursion depth exceeded");
        assert_eq!(err_obj.pos, CPYTHON_312_MAX_DEPTH * 5);
    }

    #[test]
    fn loads_with_limits_int_digit_boundary_and_error_kinds() {
        assert_eq!(DEFAULT_INT_MAX_STR_DIGITS, 4300);
        assert_eq!(CPYTHON_312_MAX_DEPTH, 9997);

        // Positive 4300-digit boundary: accepted at 4300, rejected at 4301.
        let ok_4300 = format!("1{}", "0".repeat(4299));
        assert_eq!(
            loads_with_limits(&ok_4300, None, Some(DEFAULT_INT_MAX_STR_DIGITS)).unwrap(),
            Value::Int(ok_4300)
        );

        let too_big = format!("1{}", "0".repeat(4300));
        let err_pos =
            loads_with_limits(&too_big, None, Some(DEFAULT_INT_MAX_STR_DIGITS)).unwrap_err();
        assert_eq!(err_pos.kind(), JsonErrorKind::IntDigitLimit);
        assert_eq!(err_pos.recursion_message(), None);
        assert_eq!(
            err_pos.msg,
            "Exceeds the limit (4300 digits) for integer string conversion: value has 4301 digits; use sys.set_int_max_str_digits() to increase the limit"
        );
        assert_eq!((err_pos.line, err_pos.col, err_pos.pos), (1, 1, 0));

        // Nested 4301-digit integer records value start position.
        let nested_too_big = format!("[1, {too_big}]");
        let err_nested =
            loads_with_limits(&nested_too_big, None, Some(DEFAULT_INT_MAX_STR_DIGITS)).unwrap_err();
        assert_eq!(err_nested.kind(), JsonErrorKind::IntDigitLimit);
        assert_eq!(err_nested.recursion_message(), None);
        assert_eq!((err_nested.line, err_nested.col, err_nested.pos), (1, 5, 4));

        // Negative integer at the boundary: '-' does not count as a digit.
        let neg_4300 = format!("-{}", "9".repeat(4300));
        assert_eq!(
            loads_with_limits(&neg_4300, None, Some(DEFAULT_INT_MAX_STR_DIGITS)).unwrap(),
            Value::Int(neg_4300)
        );

        let neg_4301 = format!("-{}", "9".repeat(4301));
        let err_neg =
            loads_with_limits(&neg_4301, None, Some(DEFAULT_INT_MAX_STR_DIGITS)).unwrap_err();
        assert_eq!(err_neg.kind(), JsonErrorKind::IntDigitLimit);
        assert_eq!(err_neg.recursion_message(), None);
        assert_eq!(
            err_neg.msg,
            "Exceeds the limit (4300 digits) for integer string conversion: value has 4301 digits; use sys.set_int_max_str_digits() to increase the limit"
        );
        assert_eq!((err_neg.line, err_neg.col, err_neg.pos), (1, 1, 0));

        // Float with 4301 integer digits is not capped; unlimited `loads`/`loads_with`/`loads_with_limits(..., None)` remain unlimited.
        let float_4301 = format!("{too_big}.0");
        assert!(matches!(
            loads_with_limits(&float_4301, None, Some(DEFAULT_INT_MAX_STR_DIGITS)),
            Ok(Value::Float(f)) if f.is_infinite()
        ));
        assert_eq!(loads(&too_big).unwrap(), Value::Int(too_big.clone()));
        assert_eq!(
            loads_with(&too_big, &LoadOptions::default()).unwrap(),
            Value::Int(too_big.clone())
        );
        assert_eq!(
            loads_with_limits(&too_big, None, None).unwrap(),
            Value::Int(too_big)
        );

        // `kind()` and `recursion_message()` across every error class.
        for decode_input in ["", "[1 2]", r#""\x""#, r#""\u12""#, "\"a\nb\"", "{} x"] {
            let err = loads_with_limits(
                decode_input,
                Some(CPYTHON_312_MAX_DEPTH),
                Some(DEFAULT_INT_MAX_STR_DIGITS),
            )
            .unwrap_err();
            assert_eq!(err.kind(), JsonErrorKind::Decode, "{decode_input:?}");
            assert_eq!(err.recursion_message(), None, "{decode_input:?}");
        }

        let err_bom = loads_with_limits(
            "\u{feff}{}",
            Some(CPYTHON_312_MAX_DEPTH),
            Some(DEFAULT_INT_MAX_STR_DIGITS),
        )
        .unwrap_err();
        assert_eq!(err_bom.kind(), JsonErrorKind::Decode);
        assert_eq!(err_bom.recursion_message(), None);

        let err_rec_arr = loads_with_limits("[[]]", Some(1), None).unwrap_err();
        assert_eq!(err_rec_arr.kind(), JsonErrorKind::Recursion);
        assert_eq!(
            err_rec_arr.recursion_message(),
            Some("maximum recursion depth exceeded while decoding a JSON array from a unicode string")
        );

        let err_rec_obj = loads_with_limits("[{}]", Some(1), None).unwrap_err();
        assert_eq!(err_rec_obj.kind(), JsonErrorKind::Recursion);
        assert_eq!(
            err_rec_obj.recursion_message(),
            Some("maximum recursion depth exceeded while decoding a JSON object from a unicode string")
        );
    }

    #[test]
    fn loads_codepoints_preserves_lone_surrogates_and_int_limit() {
        let cps = |s: &str| -> Vec<u32> { s.chars().map(|c| c as u32).collect() };
        let opts = CodepointLoadOptions {
            max_depth: Some(CPYTHON_312_MAX_DEPTH),
            max_int_digits: Some(DEFAULT_INT_MAX_STR_DIGITS),
        };

        let raw = loads_codepoints(
            &cps(&bs(
                r#"{"|ud800": 1, "|ud801": 2, "pair": "|ud83d|ude00|ud800|u0041|ud800|ud83d|ude00"}"#,
            )),
            &opts,
        )
        .unwrap();
        assert_eq!(
            raw,
            CodepointValue::Obj(vec![
                (vec![0xD800], CodepointValue::Int("1".into())),
                (vec![0xD801], CodepointValue::Int("2".into())),
                (
                    cps("pair"),
                    CodepointValue::Str(vec![0x1F600, 0xD800, 'A' as u32, 0xD800, 0x1F600])
                ),
            ])
        );

        // Duplicate lone-surrogate key keeps first position and last value.
        let dup_surr =
            loads_codepoints(&cps(&bs(r#"{"|ud800": 1, "b": 2, "|ud800": 3}"#)), &opts).unwrap();
        assert_eq!(
            dup_surr,
            CodepointValue::Obj(vec![
                (vec![0xD800], CodepointValue::Int("3".into())),
                (cps("b"), CodepointValue::Int("2".into())),
            ])
        );

        // Literal surrogate code point inside quoted JSON string survives.
        let literal_surr = vec!['"' as u32, 0xD800, '"' as u32];
        assert_eq!(
            loads_codepoints(&literal_surr, &opts).unwrap(),
            CodepointValue::Str(vec![0xD800])
        );
        // Bare surrogate code point outside string fails like CPython.
        let err_bare = loads_codepoints(&[0xD800], &opts).unwrap_err();
        assert_eq!(err_bare.kind(), JsonErrorKind::Decode);
        assert_eq!(err_bare.recursion_message(), None);
        assert_eq!(
            err_bare.python_str(),
            "Expecting value: line 1 column 1 (char 0)"
        );

        // Integer digit cap: 4300 OK, 4301 fails with IntDigitLimit; 4301 float OK.
        let ok_4300 = format!("-{}", "9".repeat(4300));
        assert!(loads_codepoints(&cps(&ok_4300), &opts).is_ok());

        let too_big = format!("1{}", "0".repeat(4300));
        let err_int = loads_codepoints(&cps(&too_big), &opts).unwrap_err();
        assert_eq!(err_int.kind(), JsonErrorKind::IntDigitLimit);
        assert_eq!(err_int.recursion_message(), None);
        assert_eq!(
            err_int.msg,
            "Exceeds the limit (4300 digits) for integer string conversion: value has 4301 digits; use sys.set_int_max_str_digits() to increase the limit"
        );

        let too_big_neg = format!("-{}", "9".repeat(4301));
        assert_eq!(
            loads_codepoints(&cps(&too_big_neg), &opts)
                .unwrap_err()
                .kind(),
            JsonErrorKind::IntDigitLimit
        );

        let float_4301 = format!("1{}.0", "0".repeat(4300));
        assert!(matches!(
            loads_codepoints(&cps(&float_4301), &opts),
            Ok(CodepointValue::Float(f)) if f.is_infinite()
        ));
    }

    #[test]
    fn loads_codepoints_depth_9997_and_error_kinds() {
        let opts = CodepointLoadOptions {
            max_depth: Some(CPYTHON_312_MAX_DEPTH),
            max_int_digits: Some(DEFAULT_INT_MAX_STR_DIGITS),
        };
        let arr_ok: Vec<u32> = format!(
            "{}{}",
            "[".repeat(CPYTHON_312_MAX_DEPTH),
            "]".repeat(CPYTHON_312_MAX_DEPTH)
        )
        .chars()
        .map(|c| c as u32)
        .collect();
        let parsed = loads_codepoints(&arr_ok, &opts).unwrap();
        drop(parsed);

        let arr_fail: Vec<u32> = format!(
            "{}{}",
            "[".repeat(CPYTHON_312_MAX_DEPTH + 1),
            "]".repeat(CPYTHON_312_MAX_DEPTH + 1)
        )
        .chars()
        .map(|c| c as u32)
        .collect();
        let err_arr = match loads_codepoints(&arr_fail, &opts) {
            Err(e) => e,
            Ok(v) => {
                drop(v);
                panic!("expected codepoints array recursion error at depth 9998");
            }
        };
        assert_eq!(err_arr.kind(), JsonErrorKind::Recursion);
        assert_eq!(
            err_arr.recursion_message(),
            Some("maximum recursion depth exceeded while decoding a JSON array from a unicode string")
        );

        let obj_ok: Vec<u32> = format!(
            "{}1{}",
            "{\"a\":".repeat(CPYTHON_312_MAX_DEPTH),
            "}".repeat(CPYTHON_312_MAX_DEPTH)
        )
        .chars()
        .map(|c| c as u32)
        .collect();
        let parsed_obj = loads_codepoints(&obj_ok, &opts).unwrap();
        drop(parsed_obj);

        let obj_fail: Vec<u32> = format!(
            "{}1{}",
            "{\"a\":".repeat(CPYTHON_312_MAX_DEPTH + 1),
            "}".repeat(CPYTHON_312_MAX_DEPTH + 1)
        )
        .chars()
        .map(|c| c as u32)
        .collect();
        let err_obj = match loads_codepoints(&obj_fail, &opts) {
            Err(e) => e,
            Ok(v) => {
                drop(v);
                panic!("expected codepoints object recursion error at depth 9998");
            }
        };
        assert_eq!(err_obj.kind(), JsonErrorKind::Recursion);
        assert_eq!(
            err_obj.recursion_message(),
            Some("maximum recursion depth exceeded while decoding a JSON object from a unicode string")
        );
    }

    #[test]
    fn depth_9997_scope_drop_and_multi_child_safe_on_2mib_thread() {
        const D: usize = CPYTHON_312_MAX_DEPTH;
        const SMALL: usize = 3;

        let run_2mib = |name: &'static str, f: fn()| {
            let h = std::thread::Builder::new()
                .name(name.into())
                .stack_size(2 * 1024 * 1024)
                .spawn(f)
                .unwrap();
            h.join()
                .unwrap_or_else(|e| panic!("{name} panicked: {e:?}"));
        };

        fn verify_value_tree(doc: String, doc_diff: String, doc_float: String, small_doc: String) {
            let small_v = loads(&small_doc).unwrap();
            let v = loads(&doc).unwrap();
            let w = v.clone();
            let v_diff = loads(&doc_diff).unwrap();
            let v_float = loads(&doc_float).unwrap();

            assert_eq!(v == w, true);
            assert_eq!(v == v_diff, false);
            assert_eq!(py_eq(&v, &w), true);
            assert_eq!(py_eq(&v, &v_float), true);
            assert_eq!(py_eq(&v, &v_diff), false);

            let repr_len = v.py_repr().len();
            assert!(repr_len >= small_v.py_repr().len());
            let dumped = dumps(&v);
            assert_eq!(loads(&dumped).unwrap() == v, true);
            let compact = dumps_with(&v, &DumpOptions::compact());
            assert_eq!(loads(&compact).unwrap() == v, true);
            let indent0 = DumpOptions {
                indent: Some(0),
                ..DumpOptions::default()
            };
            let indented = dumps_with(&v, &indent0);
            assert_eq!(loads(&indented).unwrap() == v, true);
            // Implicit scope-end Drop runs here for v, w, v_diff, v_float, small_v.
        }

        fn verify_cp_tree(doc: String, doc_diff: String) {
            let to_cps = |s: &str| -> Vec<u32> { s.chars().map(|c| c as u32).collect() };
            let opts = CodepointLoadOptions::default();
            let cp = loads_codepoints(&to_cps(&doc), &opts).unwrap();
            let cw = cp.clone();
            let cp_diff = loads_codepoints(&to_cps(&doc_diff), &opts).unwrap();
            assert_eq!(cp == cw, true);
            assert_eq!(cp == cp_diff, false);
            // Implicit scope-end Drop runs here for cp, cw, cp_diff.
        }

        run_2mib("val_arr_last_9997", || {
            let mk = |n: usize, leaf: &str| format!("{}{leaf}{}", "[1, ".repeat(n), "]".repeat(n));
            verify_value_tree(mk(D, "1"), mk(D, "2"), mk(D, "1.0"), mk(SMALL, "1"));
        });

        run_2mib("val_arr_first_9997", || {
            let mk = |n: usize, leaf: &str| format!("{}{leaf}{}", "[".repeat(n), ", 1]".repeat(n));
            verify_value_tree(mk(D, "1"), mk(D, "2"), mk(D, "1.0"), mk(SMALL, "1"));
        });

        run_2mib("val_obj_last_9997", || {
            let mk = |n: usize, leaf: &str| {
                format!("{}{leaf}{}", r#"{"x": 1, "a": "#.repeat(n), "}".repeat(n))
            };
            verify_value_tree(mk(D, "1"), mk(D, "2"), mk(D, "1.0"), mk(SMALL, "1"));
        });

        run_2mib("val_obj_first_9997", || {
            let mk = |n: usize, leaf: &str| {
                format!(
                    "{}{leaf}{}",
                    r#"{"a": "#.repeat(n),
                    r#", "x": 1}"#.repeat(n)
                )
            };
            verify_value_tree(mk(D, "1"), mk(D, "2"), mk(D, "1.0"), mk(SMALL, "1"));
        });

        run_2mib("cp_arr_last_first_9997", || {
            let mk_last =
                |n: usize, leaf: &str| format!("{}{leaf}{}", "[1,".repeat(n), "]".repeat(n));
            verify_cp_tree(mk_last(D, "1"), mk_last(D, "2"));

            let mk_first =
                |n: usize, leaf: &str| format!("{}{leaf}{}", "[".repeat(n), ",1]".repeat(n));
            verify_cp_tree(mk_first(D, "1"), mk_first(D, "2"));
        });

        run_2mib("cp_obj_last_first_9997", || {
            let mk_last = |n: usize, leaf: &str| {
                format!("{}{leaf}{}", r#"{"x":1,"a":"#.repeat(n), "}".repeat(n))
            };
            verify_cp_tree(mk_last(D, "1"), mk_last(D, "2"));

            let mk_first = |n: usize, leaf: &str| {
                format!("{}{leaf}{}", r#"{"a":"#.repeat(n), r#","x":1}"#.repeat(n))
            };
            verify_cp_tree(mk_first(D, "1"), mk_first(D, "2"));
        });
    }
}
