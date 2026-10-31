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

//! `shlex.quote` and `shlex.split` (POSIX mode), for the backstop's command.

/// `shlex.quote(s)`.
pub fn quote(s: &str) -> String {
    if s.is_empty() {
        return "''".into();
    }
    let safe = s
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || "_@%+=:,./-".contains(c));
    if safe {
        return s.to_string();
    }
    format!("'{}'", s.replace('\'', "'\"'\"'"))
}

/// `shlex.split(s)`; None where it raises ValueError (an open quote or a trailing backslash).
pub fn split(s: &str) -> Option<Vec<String>> {
    let t: Vec<char> = s.chars().collect();
    let ws = |c: char| matches!(c, ' ' | '\t' | '\r' | '\n');
    let mut words = Vec::new();
    let mut cur = String::new();
    let mut in_word = false;
    let mut i = 0;
    while i < t.len() {
        let c = t[i];
        if ws(c) {
            if in_word {
                words.push(std::mem::take(&mut cur));
                in_word = false;
            }
            i += 1;
            continue;
        }
        in_word = true;
        match c {
            '\\' => {
                i += 1;
                if i >= t.len() {
                    return None; // No escaped character
                }
                cur.push(t[i]);
                i += 1;
            }
            '\'' => {
                i += 1;
                loop {
                    if i >= t.len() {
                        return None; // No closing quotation
                    }
                    if t[i] == '\'' {
                        i += 1;
                        break;
                    }
                    cur.push(t[i]);
                    i += 1;
                }
            }
            '"' => {
                i += 1;
                loop {
                    if i >= t.len() {
                        return None;
                    }
                    match t[i] {
                        '"' => {
                            i += 1;
                            break;
                        }
                        '\\' => {
                            if i + 1 >= t.len() {
                                return None;
                            }
                            let n = t[i + 1];
                            if n != '"' && n != '\\' {
                                cur.push('\\');
                            }
                            cur.push(n);
                            i += 2;
                        }
                        other => {
                            cur.push(other);
                            i += 1;
                        }
                    }
                }
            }
            other => {
                cur.push(other);
                i += 1;
            }
        }
    }
    if in_word {
        words.push(cur);
    }
    Some(words)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn like_python() {
        assert_eq!(quote("/a/b-c_d.e"), "/a/b-c_d.e");
        assert_eq!(quote("/My Repo"), "'/My Repo'");
        assert_eq!(quote(""), "''");
        assert_eq!(
            split(r#"/bin/sh -c 'a "b" \c' x "y\"z\q" '' w\ v"#).unwrap(),
            vec!["/bin/sh", "-c", r#"a "b" \c"#, "x", r#"y"z\q"#, "", "w v"]
        );
        assert_eq!(split("'open"), None);
        assert_eq!(split("trailing\\"), None);
    }
}
