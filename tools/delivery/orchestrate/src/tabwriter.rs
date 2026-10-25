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

//! text/tabwriter, as printSummary configures it: minwidth 0, tabwidth 0,
//! padding 2, padded with spaces, no flags. A port of Go's column-block
//! algorithm (not a "pad every column to its widest cell" shortcut), so a
//! cell holding a tab, newline or form feed lays out exactly as Go's does.

#[derive(Clone, Copy, Default)]
struct Cell {
    size: usize,
    width: usize,
}

pub struct TabWriter {
    padding: usize,
    buf: Vec<u8>,
    pos: usize,
    cell: Cell,
    lines: Vec<Vec<Cell>>,
    widths: Vec<usize>,
    out: Vec<u8>,
}

impl TabWriter {
    pub fn new(padding: usize) -> TabWriter {
        let mut t = TabWriter {
            padding,
            buf: Vec::new(),
            pos: 0,
            cell: Cell::default(),
            lines: Vec::new(),
            widths: Vec::new(),
            out: Vec::new(),
        };
        t.reset();
        t
    }

    fn reset(&mut self) {
        self.buf.clear();
        self.pos = 0;
        self.cell = Cell::default();
        self.lines.clear();
        self.widths.clear();
        self.lines.push(Vec::new());
    }

    fn append(&mut self, text: &[u8]) {
        self.buf.extend_from_slice(text);
        self.cell.size += text.len();
    }

    fn update_width(&mut self) {
        self.cell.width += rune_count(&self.buf[self.pos..]);
        self.pos = self.buf.len();
    }

    fn terminate_cell(&mut self) -> usize {
        let line = self.lines.last_mut().unwrap();
        line.push(self.cell);
        self.cell = Cell::default();
        line.len()
    }

    pub fn write(&mut self, data: &[u8]) {
        let mut n = 0;
        for (i, &ch) in data.iter().enumerate() {
            if matches!(ch, b'\t' | 0x0b | b'\n' | 0x0c) {
                self.append(&data[n..i]);
                self.update_width();
                n = i + 1;
                let ncells = self.terminate_cell();
                if ch == b'\n' || ch == 0x0c {
                    self.lines.push(Vec::new());
                    if ch == 0x0c || ncells == 1 {
                        self.flush_internal();
                    }
                }
            }
        }
        self.append(&data[n..]);
    }

    fn flush_internal(&mut self) {
        if self.cell.size > 0 {
            self.update_width();
            self.terminate_cell();
        }
        let n = self.lines.len();
        self.format(0, 0, n);
        self.reset();
    }

    /// Flush, returning everything written.
    pub fn finish(mut self) -> Vec<u8> {
        self.flush_internal();
        self.out
    }

    fn format(&mut self, pos0: usize, mut line0: usize, line1: usize) -> usize {
        let mut pos = pos0;
        let column = self.widths.len();
        let mut this = line0;
        while this < line1 {
            if column + 1 >= self.lines[this].len() {
                this += 1;
                continue;
            }
            pos = self.write_lines(pos, line0, this);
            line0 = this;
            let mut width = 0;
            while this < line1 {
                let line = &self.lines[this];
                if column + 1 >= line.len() {
                    break;
                }
                let w = line[column].width + self.padding;
                if w > width {
                    width = w;
                }
                this += 1;
            }
            self.widths.push(width);
            pos = self.format(pos, line0, this);
            self.widths.pop();
            line0 = this;
        }
        self.write_lines(pos, line0, line1)
    }

    fn write_lines(&mut self, pos0: usize, line0: usize, line1: usize) -> usize {
        let mut pos = pos0;
        for i in line0..line1 {
            for j in 0..self.lines[i].len() {
                let c = self.lines[i][j];
                if c.size > 0 {
                    self.out.extend_from_slice(&self.buf[pos..pos + c.size]);
                    pos += c.size;
                }
                if j < self.widths.len() {
                    let pad = self.widths[j].saturating_sub(c.width);
                    self.out.extend(std::iter::repeat(b' ').take(pad));
                }
            }
            if i + 1 == self.lines.len() {
                let end = pos + self.cell.size;
                self.out.extend_from_slice(&self.buf[pos..end]);
                pos = end;
            } else {
                self.out.push(b'\n');
            }
        }
        pos
    }
}

/// utf8.RuneCount.
fn rune_count(b: &[u8]) -> usize {
    crate::json::go_string(b).chars().count()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aligns_like_go() {
        let mut t = TabWriter::new(2);
        t.write(b"  UNIT\tAFFECTED\tBY\tWHY\n");
        t.write(b"  oauth-user-inspector\ttrue\tpaths\tpath matched x\n");
        let got = String::from_utf8(t.finish()).unwrap();
        assert_eq!(
            got,
            "  UNIT                  AFFECTED  BY     WHY\n  oauth-user-inspector  true      paths  path matched x\n"
        );
    }
}
