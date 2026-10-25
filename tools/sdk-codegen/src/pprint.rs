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

//! `pprint.pformat(value, width, sort_dicts=False)` from Python 3.12, for a
//! value JSON made: what jsonschema prints under a SchemaError.

use crate::json::Value;
use crate::pystr;

pub fn pformat(value: &Value, width: usize) -> String {
    let mut out = String::new();
    format(value, &mut out, 0, 0, 0, width as isize);
    out
}

fn format(
    value: &Value,
    out: &mut String,
    indent: isize,
    allowance: isize,
    level: usize,
    width: isize,
) {
    let rep = value.py_repr();
    let max_width = width - indent - allowance;
    if (pystr::len(&rep) as isize) > max_width {
        match value {
            Value::Obj(items) if !items.is_empty() => {
                out.push('{');
                format_dict_items(items, out, indent, allowance + 1, level + 1, width);
                out.push('}');
                return;
            }
            Value::Arr(items) if !items.is_empty() => {
                out.push('[');
                format_items(items, out, indent, allowance + 1, level + 1, width);
                out.push(']');
                return;
            }
            Value::Str(s) => {
                pprint_str(s, out, indent, allowance, level + 1, width);
                return;
            }
            _ => {}
        }
    }
    out.push_str(&rep);
}

fn format_dict_items(
    items: &[(String, Value)],
    out: &mut String,
    indent: isize,
    allowance: isize,
    level: usize,
    width: isize,
) {
    let indent = indent + 1;
    let delimnl = format!(",\n{}", " ".repeat(indent as usize));
    let last_index = items.len() - 1;
    for (i, (key, ent)) in items.iter().enumerate() {
        let last = i == last_index;
        let rep = pystr::repr_str(key);
        out.push_str(&rep);
        out.push_str(": ");
        format(
            ent,
            out,
            indent + pystr::len(&rep) as isize + 2,
            if last { allowance } else { 1 },
            level,
            width,
        );
        if !last {
            out.push_str(&delimnl);
        }
    }
}

fn format_items(
    items: &[Value],
    out: &mut String,
    indent: isize,
    allowance: isize,
    level: usize,
    width: isize,
) {
    let indent = indent + 1;
    let delimnl = format!(",\n{}", " ".repeat(indent as usize));
    for (i, ent) in items.iter().enumerate() {
        let last = i == items.len() - 1;
        if i > 0 {
            out.push_str(&delimnl);
        }
        format(
            ent,
            out,
            indent,
            if last { allowance } else { 1 },
            level,
            width,
        );
    }
}

/// `re.findall(r'\S*\s*', line)` without its empty last match.
fn space_parts(line: &str) -> Vec<String> {
    let chars: Vec<char> = line.chars().collect();
    let mut parts = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        let start = i;
        while i < chars.len() && !pystr::is_space(chars[i]) {
            i += 1;
        }
        while i < chars.len() && pystr::is_space(chars[i]) {
            i += 1;
        }
        parts.push(chars[start..i].iter().collect());
    }
    parts
}

fn pprint_str(
    s: &str,
    out: &mut String,
    indent: isize,
    allowance: isize,
    level: usize,
    width: isize,
) {
    if s.is_empty() {
        out.push_str(&pystr::repr_str(s));
        return;
    }
    let mut indent = indent;
    let mut allowance = allowance;
    let mut chunks: Vec<String> = Vec::new();
    let lines = pystr::splitlines(s, true);
    if level == 1 {
        indent += 1;
        allowance += 1;
    }
    let max_width = width - indent;
    let mut max_width1 = max_width;
    let mut rep = String::new();
    for (i, line) in lines.iter().enumerate() {
        rep = pystr::repr_str(line);
        if i == lines.len() - 1 {
            max_width1 -= allowance;
        }
        if pystr::len(&rep) as isize <= max_width1 {
            chunks.push(rep.clone());
        } else {
            let parts = space_parts(line);
            let mut max_width2 = max_width;
            let mut current = String::new();
            for (j, part) in parts.iter().enumerate() {
                let candidate = format!("{}{}", current, part);
                if j == parts.len() - 1 && i == lines.len() - 1 {
                    max_width2 -= allowance;
                }
                if pystr::len(&pystr::repr_str(&candidate)) as isize > max_width2 {
                    if !current.is_empty() {
                        chunks.push(pystr::repr_str(&current));
                    }
                    current = part.clone();
                } else {
                    current = candidate;
                }
            }
            if !current.is_empty() {
                chunks.push(pystr::repr_str(&current));
            }
        }
    }
    if chunks.len() == 1 {
        out.push_str(&rep);
        return;
    }
    if level == 1 {
        out.push('(');
    }
    for (i, chunk) in chunks.iter().enumerate() {
        if i > 0 {
            out.push('\n');
            out.push_str(&" ".repeat(indent.max(0) as usize));
        }
        out.push_str(chunk);
    }
    if level == 1 {
        out.push(')');
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::loads;

    #[test]
    fn short_values_stay_on_one_line() {
        let v = loads(r#"{"type": "string", "format": "regex"}"#).unwrap();
        assert_eq!(pformat(&v, 72), "{'type': 'string', 'format': 'regex'}");
    }

    #[test]
    fn long_values_wrap_as_python_wraps_them() {
        let v = loads(
            r##"{"anyOf": [{"$ref": "#/$defs/simpleTypes"}, {"type": "array", "items": {"$ref": "#/$defs/simpleTypes"}, "minItems": 1, "uniqueItems": true}]}"##,
        )
        .unwrap();
        assert_eq!(
            pformat(&v, 72),
            "{'anyOf': [{'$ref': '#/$defs/simpleTypes'},\n           {'type': 'array',\n            'items': {'$ref': '#/$defs/simpleTypes'},\n            'minItems': 1,\n            'uniqueItems': True}]}"
        );
        let s = Value::Str("word ".repeat(20));
        assert_eq!(
            pformat(&s, 72),
            "('word word word word word word word word word word word word word '\n 'word word word word word word word ')"
        );
    }
}
