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

//! `plistlib.load` for an XML property list: dict, array, string, key,
//! integer, real, true, false, date and data (the last two kept as their
//! text), with XML's entities. A binary plist, or XML that does not parse,
//! is an error, as plistlib raises one.

use crate::json::Value;

struct X<'a> {
    s: &'a [char],
    i: usize,
}

impl<'a> X<'a> {
    fn starts(&self, w: &str) -> bool {
        let w: Vec<char> = w.chars().collect();
        self.s[self.i..].starts_with(&w)
    }

    fn skip_until(&mut self, end: &str) -> Result<(), String> {
        while self.i < self.s.len() && !self.starts(end) {
            self.i += 1;
        }
        if self.i >= self.s.len() {
            return Err(format!("unclosed token: expected {}", end));
        }
        self.i += end.chars().count();
        Ok(())
    }

    /// Whitespace, comments, processing instructions and the DOCTYPE.
    fn misc(&mut self) -> Result<(), String> {
        loop {
            while self.i < self.s.len() && self.s[self.i].is_whitespace() {
                self.i += 1;
            }
            if self.starts("<!--") {
                self.skip_until("-->")?;
            } else if self.starts("<?") {
                self.skip_until("?>")?;
            } else if self.starts("<!DOCTYPE") {
                let mut depth = 0;
                while self.i < self.s.len() {
                    match self.s[self.i] {
                        '[' => depth += 1,
                        ']' => depth -= 1,
                        '>' if depth == 0 => break,
                        _ => {}
                    }
                    self.i += 1;
                }
                self.i += 1;
            } else {
                return Ok(());
            }
        }
    }

    /// `<name attrs>` or `<name/>`: the name and whether it closed itself.
    fn open(&mut self) -> Result<(String, bool), String> {
        if self.i >= self.s.len() || self.s[self.i] != '<' {
            return Err("not well-formed (invalid token)".into());
        }
        self.i += 1;
        let start = self.i;
        while self.i < self.s.len()
            && !matches!(self.s[self.i], ' ' | '\t' | '\n' | '\r' | '>' | '/')
        {
            self.i += 1;
        }
        let name: String = self.s[start..self.i].iter().collect();
        while self.i < self.s.len() && self.s[self.i] != '>' {
            self.i += 1;
        }
        if self.i >= self.s.len() {
            return Err("unclosed token".into());
        }
        let closed = self.s[self.i - 1] == '/';
        self.i += 1;
        Ok((name, closed))
    }

    fn text(&mut self, name: &str) -> Result<String, String> {
        let mut out = String::new();
        loop {
            if self.i >= self.s.len() {
                return Err("no element found".into());
            }
            if self.starts("<!--") {
                self.skip_until("-->")?;
                continue;
            }
            if self.starts("<![CDATA[") {
                self.i += 9;
                while self.i < self.s.len() && !self.starts("]]>") {
                    out.push(self.s[self.i]);
                    self.i += 1;
                }
                self.i += 3;
                continue;
            }
            let c = self.s[self.i];
            if c == '<' {
                let close = format!("</{}", name);
                if !self.starts(&close) {
                    return Err("mismatched tag".into());
                }
                self.skip_until(">")?;
                return Ok(out);
            }
            if c == '&' {
                let start = self.i;
                self.skip_until(";")?;
                let entity: String = self.s[start + 1..self.i - 1].iter().collect();
                let ch = match entity.as_str() {
                    "amp" => Some('&'),
                    "lt" => Some('<'),
                    "gt" => Some('>'),
                    "quot" => Some('"'),
                    "apos" => Some('\''),
                    e if e.starts_with("#x") => u32::from_str_radix(&e[2..], 16)
                        .ok()
                        .and_then(char::from_u32),
                    e if e.starts_with('#') => e[1..].parse::<u32>().ok().and_then(char::from_u32),
                    _ => None,
                };
                out.push(ch.ok_or("undefined entity")?);
                continue;
            }
            out.push(c);
            self.i += 1;
        }
    }

    fn value(&mut self) -> Result<Value, String> {
        self.misc()?;
        let (name, closed) = self.open()?;
        let text = |me: &mut Self| -> Result<String, String> {
            if closed {
                Ok(String::new())
            } else {
                me.text(&name)
            }
        };
        Ok(match name.as_str() {
            "dict" => {
                let mut items: Vec<(String, Value)> = Vec::new();
                if !closed {
                    loop {
                        self.misc()?;
                        if self.starts("</dict") {
                            self.skip_until(">")?;
                            break;
                        }
                        let (k, kc) = self.open()?;
                        if k != "key" {
                            return Err(format!("unexpected element {} in dict", k));
                        }
                        let key = if kc { String::new() } else { self.text("key")? };
                        let v = self.value()?;
                        match items.iter_mut().find(|(ek, _)| *ek == key) {
                            Some(slot) => slot.1 = v,
                            None => items.push((key, v)),
                        }
                    }
                }
                Value::Dict(crate::json::Dict(items))
            }
            "array" => {
                let mut items = Vec::new();
                if !closed {
                    loop {
                        self.misc()?;
                        if self.starts("</array") {
                            self.skip_until(">")?;
                            break;
                        }
                        items.push(self.value()?);
                    }
                }
                Value::List(items)
            }
            "string" | "date" | "data" => Value::Str(text(self)?),
            "integer" => {
                let t = text(self)?;
                let t = t.trim();
                let n = if let Some(h) = t.strip_prefix("0x").or_else(|| t.strip_prefix("0X")) {
                    i128::from_str_radix(h, 16).map_err(|e| e.to_string())?
                } else {
                    t.parse::<i128>().map_err(|e| e.to_string())?
                };
                Value::Int(n)
            }
            "real" => Value::Float(
                text(self)?
                    .trim()
                    .parse()
                    .map_err(|_| "could not convert string to float")?,
            ),
            "true" | "false" => {
                if !closed {
                    text(self)?;
                }
                Value::Bool(name == "true")
            }
            other => return Err(format!("unknown element {}", other)),
        })
    }
}

/// `plistlib.load(handle)` on these bytes.
pub fn load(data: &[u8]) -> Result<Value, String> {
    if data.starts_with(b"bplist00") {
        return Err("binary property lists are not read here".into());
    }
    let text = crate::pytext::decode_utf8(data)?;
    let chars: Vec<char> = text.chars().collect();
    let mut x = X { s: &chars, i: 0 };
    x.misc()?;
    let (name, closed) = x.open()?;
    if name != "plist" {
        // plistlib also takes a bare value with no <plist>.
        x.i = 0;
        x.misc()?;
        return x.value();
    }
    if closed {
        return Err("no value in the plist".into());
    }
    let v = x.value()?;
    Ok(v)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_apps_info_plist() {
        let v = load(include_bytes!("../testdata/Info.plist")).unwrap();
        assert_eq!(
            v.field("LSMinimumSystemVersion"),
            Some(&Value::Str("14.0".into()))
        );
        let v = load(
            b"<plist><dict><key>a&amp;b</key><array><integer>3</integer><true/><string/></array>\
              <!-- x --><key>r</key><real>1.5</real></dict></plist>",
        )
        .unwrap();
        assert_eq!(v.py_repr(), "{'a&b': [3, True, ''], 'r': 1.5}");
        assert!(load(b"<plist><dict><key>x</dict></plist>").is_err());
    }
}
