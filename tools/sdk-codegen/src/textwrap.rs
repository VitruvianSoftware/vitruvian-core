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

//! `textwrap.wrap(text, width)` from Python 3.12 with every other argument
//! left at its default: tabs expanded, whitespace made spaces, breaks after
//! hyphens, long words broken. `TextWrapper.wordsep_re` is matched by hand,
//! the way Python's backtracking engine matches it.

use crate::pystr;

fn ws(c: char) -> bool {
    matches!(c, '\t' | '\n' | '\x0b' | '\x0c' | '\r' | ' ')
}

/// `[\w!"'&.,?]`
fn wp(c: char) -> bool {
    pystr::is_word(c) || "!\"'&.,?".contains(c)
}

/// `[^\d\W]`
fn lt(c: char) -> bool {
    pystr::is_word(c) && !pystr::is_decimal(c)
}

struct Text {
    c: Vec<char>,
}

impl Text {
    fn at(&self, i: usize) -> Option<char> {
        self.c.get(i).copied()
    }

    fn is(&self, i: usize, test: fn(char) -> bool) -> bool {
        matches!(self.at(i), Some(c) if test(c))
    }

    /// `-{2,}\w` at i (the lookahead of an em-dash).
    fn em_dash_then_word(&self, i: usize) -> Option<usize> {
        let mut k = i;
        while self.at(k) == Some('-') {
            k += 1;
        }
        if k - i >= 2 && self.is(k, pystr::is_word) {
            Some(k)
        } else {
            None
        }
    }

    /// Where wordsep_re's match starting at i ends, if one starts there.
    fn match_at(&self, i: usize) -> Option<usize> {
        let n = self.c.len();
        if self.is(i, ws) {
            let mut j = i;
            while self.is(j, ws) {
                j += 1;
            }
            return Some(j);
        }
        if i > 0 && self.is(i - 1, wp) {
            if let Some(k) = self.em_dash_then_word(i) {
                return Some(k);
            }
        }
        let mut pos = i;
        loop {
            if pos >= n || self.is(pos, ws) {
                return None;
            }
            pos += 1;
            // A hyphen inside a word, between letters.
            if self.at(pos) == Some('-') {
                let q = pos + 1;
                let behind = (q >= 3 && self.is(q - 3, lt) && self.is(q - 2, lt))
                    || (q >= 4
                        && self.is(q - 4, lt)
                        && self.at(q - 3) == Some('-')
                        && self.is(q - 2, lt));
                let ahead = self.is(q, lt)
                    && ((self.at(q + 1) == Some('-') && self.is(q + 2, lt)) || self.is(q + 1, lt));
                if behind && ahead {
                    return Some(q);
                }
            }
            // The end of a word.
            if pos == n || self.is(pos, ws) {
                return Some(pos);
            }
            // An em-dash after it.
            if self.is(pos - 1, wp) && self.em_dash_then_word(pos).is_some() {
                return Some(pos);
            }
        }
    }

    /// `wordsep_re.split(text)` without its empty pieces.
    fn split(&self) -> Vec<String> {
        let n = self.c.len();
        let mut chunks = Vec::new();
        let mut last = 0;
        let mut start = 0;
        while start < n {
            match self.match_at(start) {
                Some(end) => {
                    chunks.push(self.c[last..start].iter().collect::<String>());
                    chunks.push(self.c[start..end].iter().collect::<String>());
                    last = end;
                    start = end;
                }
                None => start += 1,
            }
        }
        chunks.push(self.c[last..].iter().collect::<String>());
        chunks.into_iter().filter(|c| !c.is_empty()).collect()
    }
}

fn handle_long_word(
    chunks: &mut Vec<Vec<char>>,
    cur_line: &mut Vec<Vec<char>>,
    cur_len: usize,
    width: usize,
) {
    let space_left = if width < 1 { 1 } else { width - cur_len };
    let chunk = chunks.last().unwrap().clone();
    let mut end = space_left;
    if chunk.len() > space_left {
        let hyphen = chunk[..space_left.min(chunk.len())]
            .iter()
            .rposition(|&c| c == '-');
        if let Some(h) = hyphen {
            if h > 0 && chunk[..h].iter().any(|&c| c != '-') {
                end = h + 1;
            }
        }
    }
    let end = end.min(chunk.len());
    cur_line.push(chunk[..end].to_vec());
    *chunks.last_mut().unwrap() = chunk[end..].to_vec();
}

fn blank(chunk: &[char]) -> bool {
    chunk.iter().all(|&c| pystr::is_space(c))
}

/// `textwrap.wrap(text, width)`.
pub fn wrap(text: &str, width: usize) -> Vec<String> {
    let munged: String = pystr::expandtabs(text, 8)
        .chars()
        .map(|c| if ws(c) { ' ' } else { c })
        .collect();
    let split = Text {
        c: munged.chars().collect(),
    }
    .split();
    let mut chunks: Vec<Vec<char>> = split.iter().rev().map(|s| s.chars().collect()).collect();
    let mut lines: Vec<String> = Vec::new();
    while !chunks.is_empty() {
        let mut cur_line: Vec<Vec<char>> = Vec::new();
        let mut cur_len = 0usize;
        if blank(chunks.last().unwrap()) && !lines.is_empty() {
            chunks.pop();
        }
        while let Some(last) = chunks.last() {
            let l = last.len();
            if cur_len + l <= width {
                cur_line.push(chunks.pop().unwrap());
                cur_len += l;
            } else {
                break;
            }
        }
        if let Some(last) = chunks.last() {
            if last.len() > width {
                handle_long_word(&mut chunks, &mut cur_line, cur_len, width);
                cur_len = cur_line.iter().map(|c| c.len()).sum();
            }
        }
        if let Some(last) = cur_line.last() {
            if blank(last) {
                cur_len -= last.len();
                cur_line.pop();
            }
        }
        let _ = cur_len;
        if !cur_line.is_empty() {
            lines.push(cur_line.iter().flatten().collect());
        }
    }
    lines
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_as_wordsep_re_does() {
        let t = Text {
            c: "Look, goof-ball -- use the -b option!".chars().collect(),
        };
        assert_eq!(
            t.split(),
            vec![
                "Look,", " ", "goof-", "ball", " ", "--", " ", "use", " ", "the", " ", "-b", " ",
                "option!"
            ]
        );
        let t = Text {
            c: "a--b well-known x-y".chars().collect(),
        };
        assert_eq!(
            t.split(),
            vec!["a", "--", "b", " ", "well-", "known", " ", "x-y"]
        );
    }

    #[test]
    fn wraps() {
        assert_eq!(wrap("", 10), Vec::<String>::new());
        assert_eq!(wrap("   ", 10), Vec::<String>::new());
        assert_eq!(
            wrap("one two three four", 9),
            vec!["one two", "three", "four"]
        );
        assert_eq!(wrap("abcdefghijkl", 5), vec!["abcde", "fghij", "kl"]);
        assert_eq!(wrap("aaa-bbbbbbbb", 6), vec!["aaa-bb", "bbbbbb"]);
        assert_eq!(wrap("a\tb", 20), vec!["a       b"]);
    }
}
