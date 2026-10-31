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

//! `difflib.unified_diff`, as `--dry-run` prints it.
//!
//! A port of Python's SequenceMatcher (no junk function; the "popular
//! element" heuristic for 200+ lines), so the hunks are the ones install.py
//! printed, not merely a valid diff.

use std::collections::HashMap;

#[derive(Clone, Copy, PartialEq)]
enum Tag {
    Equal,
    Replace,
    Delete,
    Insert,
}

type Op = (Tag, usize, usize, usize, usize);

struct Matcher<'a> {
    a: &'a [String],
    b: &'a [String],
    b2j: HashMap<&'a str, Vec<usize>>,
}

impl<'a> Matcher<'a> {
    fn new(a: &'a [String], b: &'a [String]) -> Self {
        let mut b2j: HashMap<&str, Vec<usize>> = HashMap::new();
        for (i, line) in b.iter().enumerate() {
            b2j.entry(line.as_str()).or_default().push(i);
        }
        let n = b.len();
        if n >= 200 {
            let ntest = n / 100 + 1;
            b2j.retain(|_, idxs| idxs.len() <= ntest);
        }
        Matcher { a, b, b2j }
    }

    fn find_longest_match(
        &self,
        alo: usize,
        ahi: usize,
        blo: usize,
        bhi: usize,
    ) -> (usize, usize, usize) {
        let (mut besti, mut bestj, mut bestsize) = (alo, blo, 0usize);
        let mut j2len: HashMap<usize, usize> = HashMap::new();
        for i in alo..ahi {
            let mut newj2len: HashMap<usize, usize> = HashMap::new();
            if let Some(js) = self.b2j.get(self.a[i].as_str()) {
                for &j in js {
                    if j < blo {
                        continue;
                    }
                    if j >= bhi {
                        break;
                    }
                    let k = j
                        .checked_sub(1)
                        .and_then(|p| j2len.get(&p))
                        .copied()
                        .unwrap_or(0)
                        + 1;
                    newj2len.insert(j, k);
                    if k > bestsize {
                        besti = i + 1 - k;
                        bestj = j + 1 - k;
                        bestsize = k;
                    }
                }
            }
            j2len = newj2len;
        }
        while besti > alo && bestj > blo && self.a[besti - 1] == self.b[bestj - 1] {
            besti -= 1;
            bestj -= 1;
            bestsize += 1;
        }
        while besti + bestsize < ahi
            && bestj + bestsize < bhi
            && self.a[besti + bestsize] == self.b[bestj + bestsize]
        {
            bestsize += 1;
        }
        (besti, bestj, bestsize)
    }

    fn matching_blocks(&self) -> Vec<(usize, usize, usize)> {
        let (la, lb) = (self.a.len(), self.b.len());
        let mut queue = vec![(0, la, 0, lb)];
        let mut blocks = Vec::new();
        while let Some((alo, ahi, blo, bhi)) = queue.pop() {
            let (i, j, k) = self.find_longest_match(alo, ahi, blo, bhi);
            if k > 0 {
                blocks.push((i, j, k));
                if alo < i && blo < j {
                    queue.push((alo, i, blo, j));
                }
                if i + k < ahi && j + k < bhi {
                    queue.push((i + k, ahi, j + k, bhi));
                }
            }
        }
        blocks.sort();
        let (mut i1, mut j1, mut k1) = (0, 0, 0);
        let mut out = Vec::new();
        for (i2, j2, k2) in blocks {
            if i1 + k1 == i2 && j1 + k1 == j2 {
                k1 += k2;
            } else {
                if k1 > 0 {
                    out.push((i1, j1, k1));
                }
                i1 = i2;
                j1 = j2;
                k1 = k2;
            }
        }
        if k1 > 0 {
            out.push((i1, j1, k1));
        }
        out.push((la, lb, 0));
        out
    }

    fn opcodes(&self) -> Vec<Op> {
        let (mut i, mut j) = (0, 0);
        let mut out = Vec::new();
        for (ai, bj, size) in self.matching_blocks() {
            let tag = if i < ai && j < bj {
                Some(Tag::Replace)
            } else if i < ai {
                Some(Tag::Delete)
            } else if j < bj {
                Some(Tag::Insert)
            } else {
                None
            };
            if let Some(t) = tag {
                out.push((t, i, ai, j, bj));
            }
            i = ai + size;
            j = bj + size;
            if size > 0 {
                out.push((Tag::Equal, ai, i, bj, j));
            }
        }
        out
    }

    fn grouped_opcodes(&self, n: usize) -> Vec<Vec<Op>> {
        let mut codes = self.opcodes();
        if codes.is_empty() {
            codes = vec![(Tag::Equal, 0, 1, 0, 1)];
        }
        if codes[0].0 == Tag::Equal {
            let (t, i1, i2, j1, j2) = codes[0];
            codes[0] = (
                t,
                i1.max(i2.saturating_sub(n)),
                i2,
                j1.max(j2.saturating_sub(n)),
                j2,
            );
        }
        let last = codes.len() - 1;
        if codes[last].0 == Tag::Equal {
            let (t, i1, i2, j1, j2) = codes[last];
            codes[last] = (t, i1, i2.min(i1 + n), j1, j2.min(j1 + n));
        }
        let nn = n + n;
        let mut groups = Vec::new();
        let mut group = Vec::new();
        for (tag, mut i1, i2, mut j1, j2) in codes {
            if tag == Tag::Equal && i2 - i1 > nn {
                group.push((tag, i1, i2.min(i1 + n), j1, j2.min(j1 + n)));
                groups.push(std::mem::take(&mut group));
                i1 = i1.max(i2.saturating_sub(n));
                j1 = j1.max(j2.saturating_sub(n));
            }
            group.push((tag, i1, i2, j1, j2));
        }
        if !group.is_empty() && !(group.len() == 1 && group[0].0 == Tag::Equal) {
            groups.push(group);
        }
        groups
    }
}

fn format_range(start: usize, stop: usize) -> String {
    let mut beginning = start + 1;
    let length = stop - start;
    if length == 1 {
        return beginning.to_string();
    }
    if length == 0 {
        beginning -= 1;
    }
    format!("{},{}", beginning, length)
}

/// `"".join(difflib.unified_diff(a, b, fromfile, tofile))` (n=3, lineterm="\n").
pub fn unified_diff(a: &[String], b: &[String], fromfile: &str, tofile: &str) -> String {
    let m = Matcher::new(a, b);
    let mut out = String::new();
    for (gi, group) in m.grouped_opcodes(3).iter().enumerate() {
        if gi == 0 {
            out.push_str(&format!("--- {}\n+++ {}\n", fromfile, tofile));
        }
        let first = group[0];
        let last = group[group.len() - 1];
        out.push_str(&format!(
            "@@ -{} +{} @@\n",
            format_range(first.1, last.2),
            format_range(first.3, last.4)
        ));
        for &(tag, i1, i2, j1, j2) in group {
            if tag == Tag::Equal {
                for line in &a[i1..i2] {
                    out.push(' ');
                    out.push_str(line);
                }
                continue;
            }
            if tag == Tag::Replace || tag == Tag::Delete {
                for line in &a[i1..i2] {
                    out.push('-');
                    out.push_str(line);
                }
            }
            if tag == Tag::Replace || tag == Tag::Insert {
                for line in &b[j1..j2] {
                    out.push('+');
                    out.push_str(line);
                }
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lines(s: &str) -> Vec<String> {
        s.split_inclusive('\n').map(|l| l.to_string()).collect()
    }

    #[test]
    fn matches_pythons_hunks() {
        // python3 -c 'import difflib,sys; sys.stdout.writelines(difflib.unified_diff(a, b, "x (now)", "x (after)"))'
        let a = lines("1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n");
        let b = lines("1\n2\nthree\n4\n5\n6\n7\n8\n9\n10\neleven\n12\n13\n");
        assert_eq!(
            unified_diff(&a, &b, "x (now)", "x (after)"),
            "--- x (now)\n+++ x (after)\n@@ -1,6 +1,6 @@\n 1\n 2\n-3\n+three\n 4\n 5\n 6\n@@ -8,5 +8,6 @@\n 8\n 9\n 10\n-11\n+eleven\n 12\n+13\n"
        );
        assert_eq!(unified_diff(&a, &a, "x", "y"), "");
        assert_eq!(
            unified_diff(&[], &lines("{}\n"), "x", "y"),
            "--- x\n+++ y\n@@ -0,0 +1 @@\n+{}\n"
        );
    }
}
