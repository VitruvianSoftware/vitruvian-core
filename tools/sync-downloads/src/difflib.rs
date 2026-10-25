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

//! `difflib.unified_diff` as Python 3.12 computes it: the same
//! SequenceMatcher (no junk function, autojunk on), so the same hunks.

use std::collections::{HashMap, HashSet};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
struct Block {
    a: usize,
    b: usize,
    size: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Tag {
    Equal,
    Replace,
    Delete,
    Insert,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Op {
    tag: Tag,
    i1: usize,
    i2: usize,
    j1: usize,
    j2: usize,
}

struct Matcher<'a> {
    a: &'a [String],
    b: &'a [String],
    b2j: HashMap<&'a str, Vec<usize>>,
}

impl<'a> Matcher<'a> {
    fn new(a: &'a [String], b: &'a [String]) -> Self {
        let mut b2j: HashMap<&str, Vec<usize>> = HashMap::new();
        for (i, elt) in b.iter().enumerate() {
            b2j.entry(elt.as_str()).or_default().push(i);
        }
        // autojunk: in a sequence of 200 or more, an element that makes up
        // more than 1% of it is "popular" and not indexed.
        let n = b.len();
        if n >= 200 {
            let ntest = n / 100 + 1;
            let popular: HashSet<&str> = b2j
                .iter()
                .filter(|(_, idxs)| idxs.len() > ntest)
                .map(|(k, _)| *k)
                .collect();
            for elt in popular {
                b2j.remove(elt);
            }
        }
        Matcher { a, b, b2j }
    }

    fn find_longest_match(&self, alo: usize, ahi: usize, blo: usize, bhi: usize) -> Block {
        let (a, b) = (self.a, self.b);
        let (mut besti, mut bestj, mut bestsize) = (alo, blo, 0usize);
        let mut j2len: HashMap<usize, usize> = HashMap::new();
        let nothing: Vec<usize> = Vec::new();
        for (i, elt) in a.iter().enumerate().take(ahi).skip(alo) {
            let mut newj2len: HashMap<usize, usize> = HashMap::new();
            for &j in self.b2j.get(elt.as_str()).unwrap_or(&nothing) {
                if j < blo {
                    continue;
                }
                if j >= bhi {
                    break;
                }
                let k = if j > 0 {
                    j2len.get(&(j - 1)).copied().unwrap_or(0)
                } else {
                    0
                } + 1;
                newj2len.insert(j, k);
                if k > bestsize {
                    besti = i + 1 - k;
                    bestj = j + 1 - k;
                    bestsize = k;
                }
            }
            j2len = newj2len;
        }
        // There is no junk, so only the first two of Python's four extension
        // loops can do anything; they grow the match over popular elements.
        while besti > alo && bestj > blo && a[besti - 1] == b[bestj - 1] {
            besti -= 1;
            bestj -= 1;
            bestsize += 1;
        }
        while besti + bestsize < ahi
            && bestj + bestsize < bhi
            && a[besti + bestsize] == b[bestj + bestsize]
        {
            bestsize += 1;
        }
        Block {
            a: besti,
            b: bestj,
            size: bestsize,
        }
    }

    fn matching_blocks(&self) -> Vec<Block> {
        let (la, lb) = (self.a.len(), self.b.len());
        let mut queue = vec![(0, la, 0, lb)];
        let mut blocks = Vec::new();
        while let Some((alo, ahi, blo, bhi)) = queue.pop() {
            let x = self.find_longest_match(alo, ahi, blo, bhi);
            if x.size > 0 {
                blocks.push(x);
                if alo < x.a && blo < x.b {
                    queue.push((alo, x.a, blo, x.b));
                }
                if x.a + x.size < ahi && x.b + x.size < bhi {
                    queue.push((x.a + x.size, ahi, x.b + x.size, bhi));
                }
            }
        }
        blocks.sort();
        let mut out = Vec::new();
        let (mut i1, mut j1, mut k1) = (0, 0, 0);
        for blk in blocks {
            if i1 + k1 == blk.a && j1 + k1 == blk.b {
                k1 += blk.size;
            } else {
                if k1 > 0 {
                    out.push(Block {
                        a: i1,
                        b: j1,
                        size: k1,
                    });
                }
                i1 = blk.a;
                j1 = blk.b;
                k1 = blk.size;
            }
        }
        if k1 > 0 {
            out.push(Block {
                a: i1,
                b: j1,
                size: k1,
            });
        }
        out.push(Block {
            a: la,
            b: lb,
            size: 0,
        });
        out
    }

    fn opcodes(&self) -> Vec<Op> {
        let (mut i, mut j) = (0, 0);
        let mut answer = Vec::new();
        for blk in self.matching_blocks() {
            let tag = if i < blk.a && j < blk.b {
                Some(Tag::Replace)
            } else if i < blk.a {
                Some(Tag::Delete)
            } else if j < blk.b {
                Some(Tag::Insert)
            } else {
                None
            };
            if let Some(tag) = tag {
                answer.push(Op {
                    tag,
                    i1: i,
                    i2: blk.a,
                    j1: j,
                    j2: blk.b,
                });
            }
            i = blk.a + blk.size;
            j = blk.b + blk.size;
            if blk.size > 0 {
                answer.push(Op {
                    tag: Tag::Equal,
                    i1: blk.a,
                    i2: i,
                    j1: blk.b,
                    j2: j,
                });
            }
        }
        answer
    }

    fn grouped_opcodes(&self, n: usize) -> Vec<Vec<Op>> {
        let mut codes = self.opcodes();
        if codes.is_empty() {
            codes.push(Op {
                tag: Tag::Equal,
                i1: 0,
                i2: 1,
                j1: 0,
                j2: 1,
            });
        }
        if codes[0].tag == Tag::Equal {
            let c = &mut codes[0];
            c.i1 = c.i1.max(c.i2.saturating_sub(n));
            c.j1 = c.j1.max(c.j2.saturating_sub(n));
        }
        let last = codes.len() - 1;
        if codes[last].tag == Tag::Equal {
            let c = &mut codes[last];
            c.i2 = c.i2.min(c.i1 + n);
            c.j2 = c.j2.min(c.j1 + n);
        }
        let nn = n + n;
        let mut groups = Vec::new();
        let mut group: Vec<Op> = Vec::new();
        for mut c in codes {
            if c.tag == Tag::Equal && c.i2 - c.i1 > nn {
                group.push(Op {
                    tag: Tag::Equal,
                    i1: c.i1,
                    i2: c.i2.min(c.i1 + n),
                    j1: c.j1,
                    j2: c.j2.min(c.j1 + n),
                });
                groups.push(std::mem::take(&mut group));
                c.i1 = c.i1.max(c.i2.saturating_sub(n));
                c.j1 = c.j1.max(c.j2.saturating_sub(n));
            }
            group.push(c);
        }
        if !group.is_empty() && (group.len() != 1 || group[0].tag != Tag::Equal) {
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

/// `"".join(difflib.unified_diff(a, b, fromfile, tofile))` with n=3.
pub fn unified_diff(a: &[String], b: &[String], fromfile: &str, tofile: &str) -> String {
    let m = Matcher::new(a, b);
    let mut out = String::new();
    for (gi, group) in m.grouped_opcodes(3).iter().enumerate() {
        if gi == 0 {
            out.push_str(&format!("--- {}\n+++ {}\n", fromfile, tofile));
        }
        let (first, last) = (group[0], group[group.len() - 1]);
        out.push_str(&format!(
            "@@ -{} +{} @@\n",
            format_range(first.i1, last.i2),
            format_range(first.j1, last.j2)
        ));
        for op in group {
            if op.tag == Tag::Equal {
                for line in &a[op.i1..op.i2] {
                    out.push(' ');
                    out.push_str(line);
                }
                continue;
            }
            if matches!(op.tag, Tag::Replace | Tag::Delete) {
                for line in &a[op.i1..op.i2] {
                    out.push('-');
                    out.push_str(line);
                }
            }
            if matches!(op.tag, Tag::Replace | Tag::Insert) {
                for line in &b[op.j1..op.j2] {
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
        crate::pystr::splitlines_keepends(s)
    }

    #[test]
    fn identical_is_empty() {
        let a = lines("a\nb\n");
        assert_eq!(unified_diff(&a, &a, "a/x", "b/x"), "");
    }

    #[test]
    fn one_change_with_context() {
        let a = lines("1\n2\n3\n4\n5\n6\n7\n8\n9\n");
        let b = lines("1\n2\n3\n4\nFIVE\n6\n7\n8\n9\n");
        assert_eq!(
            unified_diff(&a, &b, "a/x", "b/x"),
            "--- a/x\n+++ b/x\n@@ -2,7 +2,7 @@\n 2\n 3\n 4\n-5\n+FIVE\n 6\n 7\n 8\n"
        );
    }

    #[test]
    fn far_apart_changes_make_two_hunks_and_no_final_newline() {
        let a: Vec<String> = (0..20).map(|i| format!("{}\n", i)).collect();
        let mut b = a.clone();
        b[1] = "x\n".into();
        b[19] = "y".into();
        let d = unified_diff(&a, &b, "a", "b");
        assert_eq!(d.matches("@@ -").count(), 2);
        assert!(d.contains("@@ -1,5 +1,5 @@\n 0\n-1\n+x\n"));
        assert!(d.ends_with("-19\n+y"));
    }
}
