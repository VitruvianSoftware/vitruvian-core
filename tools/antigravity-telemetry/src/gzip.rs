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

//! `gzip.compress` without a crate: RFC 1952 framing around one RFC 1951
//! block using the fixed Huffman code and greedy LZ77 over a 32 KiB window.
//!
//! The output is not byte-identical to zlib's (the collector only needs it to
//! be valid gzip), but OTLP JSON is repetitive enough that the fixed code
//! already shrinks it several-fold.

const WINDOW: usize = 32 * 1024;
const MIN_MATCH: usize = 3;
const MAX_MATCH: usize = 258;
const HASH_BITS: u32 = 15;
const MAX_CHAIN: usize = 64;

const LEN_BASE: [u16; 29] = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131,
    163, 195, 227, 258,
];
const LEN_EXTRA: [u8; 29] = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
];
const DIST_BASE: [u16; 30] = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
    2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
];
const DIST_EXTRA: [u8; 30] = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13,
    13,
];

/// CRC-32 (IEEE 802.3), as gzip's trailer needs.
pub fn crc32(data: &[u8]) -> u32 {
    let mut table = [0u32; 256];
    for (i, slot) in table.iter_mut().enumerate() {
        let mut c = i as u32;
        for _ in 0..8 {
            c = if c & 1 != 0 {
                0xEDB8_8320 ^ (c >> 1)
            } else {
                c >> 1
            };
        }
        *slot = c;
    }
    let mut crc = 0xFFFF_FFFFu32;
    for b in data {
        crc = table[((crc ^ *b as u32) & 0xff) as usize] ^ (crc >> 8);
    }
    crc ^ 0xFFFF_FFFF
}

struct BitWriter {
    out: Vec<u8>,
    acc: u64,
    nbits: u32,
}

impl BitWriter {
    fn new() -> Self {
        BitWriter {
            out: Vec::new(),
            acc: 0,
            nbits: 0,
        }
    }

    /// Append `n` bits of `value`, least significant first.
    fn bits(&mut self, value: u32, n: u32) {
        self.acc |= (value as u64) << self.nbits;
        self.nbits += n;
        while self.nbits >= 8 {
            self.out.push(self.acc as u8);
            self.acc >>= 8;
            self.nbits -= 8;
        }
    }

    /// Append a Huffman code, which DEFLATE stores most significant bit first.
    fn code(&mut self, code: u32, len: u32) {
        let mut rev = 0u32;
        for i in 0..len {
            rev |= ((code >> i) & 1) << (len - 1 - i);
        }
        self.bits(rev, len);
    }

    fn finish(mut self) -> Vec<u8> {
        if self.nbits > 0 {
            self.out.push(self.acc as u8);
        }
        self.out
    }
}

fn literal(w: &mut BitWriter, sym: u32) {
    match sym {
        0..=143 => w.code(0x30 + sym, 8),
        144..=255 => w.code(0x190 + (sym - 144), 9),
        256..=279 => w.code(sym - 256, 7),
        _ => w.code(0xC0 + (sym - 280), 8),
    }
}

fn length(w: &mut BitWriter, len: usize) {
    let idx = LEN_BASE
        .iter()
        .rposition(|b| *b as usize <= len)
        .expect("len >= 3");
    literal(w, 257 + idx as u32);
    let extra = LEN_EXTRA[idx] as u32;
    if extra > 0 {
        w.bits((len - LEN_BASE[idx] as usize) as u32, extra);
    }
}

fn distance(w: &mut BitWriter, dist: usize) {
    let idx = DIST_BASE
        .iter()
        .rposition(|b| *b as usize <= dist)
        .expect("dist >= 1");
    w.code(idx as u32, 5);
    let extra = DIST_EXTRA[idx] as u32;
    if extra > 0 {
        w.bits((dist - DIST_BASE[idx] as usize) as u32, extra);
    }
}

fn hash3(data: &[u8], i: usize) -> usize {
    let v = (data[i] as u32) << 16 | (data[i + 1] as u32) << 8 | data[i + 2] as u32;
    (v.wrapping_mul(0x9E37_79B1) >> (32 - HASH_BITS)) as usize
}

/// Raw DEFLATE (RFC 1951) of `data` as a single fixed-Huffman block.
pub fn deflate(data: &[u8]) -> Vec<u8> {
    let mut w = BitWriter::new();
    w.bits(1, 1); // BFINAL
    w.bits(1, 2); // BTYPE = 01, fixed Huffman

    let mut head = vec![usize::MAX; 1 << HASH_BITS];
    let mut prev = vec![usize::MAX; data.len()];
    let insert = |head: &mut Vec<usize>, prev: &mut Vec<usize>, i: usize| {
        if i + MIN_MATCH <= data.len() {
            let h = hash3(data, i);
            prev[i] = head[h];
            head[h] = i;
        }
    };

    let mut i = 0;
    while i < data.len() {
        let mut best_len = 0;
        let mut best_dist = 0;
        if i + MIN_MATCH <= data.len() {
            let mut cand = head[hash3(data, i)];
            let mut chain = 0;
            let max_len = MAX_MATCH.min(data.len() - i);
            while cand != usize::MAX && i - cand <= WINDOW && chain < MAX_CHAIN {
                let mut l = 0;
                while l < max_len && data[cand + l] == data[i + l] {
                    l += 1;
                }
                if l > best_len {
                    best_len = l;
                    best_dist = i - cand;
                    if l == max_len {
                        break;
                    }
                }
                cand = prev[cand];
                chain += 1;
            }
        }
        if best_len >= MIN_MATCH {
            length(&mut w, best_len);
            distance(&mut w, best_dist);
            for j in i..i + best_len {
                insert(&mut head, &mut prev, j);
            }
            i += best_len;
        } else {
            literal(&mut w, data[i] as u32);
            insert(&mut head, &mut prev, i);
            i += 1;
        }
    }
    literal(&mut w, 256); // end of block
    w.finish()
}

/// `gzip.compress(data)`.
pub fn compress(data: &[u8]) -> Vec<u8> {
    let mut out = vec![0x1f, 0x8b, 8, 0];
    let mtime = (crate::sys::now_secs() as u64 & 0xFFFF_FFFF) as u32;
    out.extend_from_slice(&mtime.to_le_bytes());
    out.push(0); // XFL
    out.push(255); // OS: unknown, as CPython writes
    out.extend_from_slice(&deflate(data));
    out.extend_from_slice(&crc32(data).to_le_bytes());
    out.extend_from_slice(&(data.len() as u32).to_le_bytes());
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A minimal inflater for fixed-Huffman blocks, to round-trip the encoder.
    fn inflate_fixed(input: &[u8]) -> Vec<u8> {
        struct R<'a> {
            d: &'a [u8],
            pos: usize,
        }
        impl<'a> R<'a> {
            fn bit(&mut self) -> u32 {
                let b = (self.d[self.pos / 8] >> (self.pos % 8)) & 1;
                self.pos += 1;
                b as u32
            }
            fn bits(&mut self, n: u32) -> u32 {
                (0..n).fold(0, |acc, i| acc | (self.bit() << i))
            }
            fn code(&mut self, n: u32) -> u32 {
                (0..n).fold(0, |acc, _| (acc << 1) | self.bit())
            }
        }
        let mut r = R { d: input, pos: 0 };
        assert_eq!(r.bits(1), 1);
        assert_eq!(r.bits(2), 1);
        let mut out: Vec<u8> = Vec::new();
        loop {
            let mut c = r.code(7);
            let sym = if c <= 0x17 {
                c + 256
            } else {
                c = (c << 1) | r.bit();
                if (0x30..=0xBF).contains(&c) {
                    c - 0x30
                } else if (0xC0..=0xC7).contains(&c) {
                    c - 0xC0 + 280
                } else {
                    c = (c << 1) | r.bit();
                    c - 0x190 + 144
                }
            };
            match sym.cmp(&256) {
                std::cmp::Ordering::Less => out.push(sym as u8),
                std::cmp::Ordering::Equal => break,
                std::cmp::Ordering::Greater => {
                    let li = (sym - 257) as usize;
                    let len = LEN_BASE[li] as usize + r.bits(LEN_EXTRA[li] as u32) as usize;
                    let di = r.code(5) as usize;
                    let dist = DIST_BASE[di] as usize + r.bits(DIST_EXTRA[di] as u32) as usize;
                    let start = out.len() - dist;
                    for k in 0..len {
                        let b = out[start + k];
                        out.push(b);
                    }
                }
            }
        }
        out
    }

    #[test]
    fn crc_known_vector() {
        assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
    }

    #[test]
    fn deflate_round_trips() {
        let mut big = Vec::new();
        for i in 0..5000u32 {
            big.extend_from_slice(
                format!("{{\"key\": \"value-{}\", \"n\": {}}}, ", i % 37, i).as_bytes(),
            );
        }
        let cases: Vec<Vec<u8>> = vec![
            vec![],
            b"a".to_vec(),
            b"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_vec(),
            (0..=255u8).cycle().take(70_000).collect(),
            big,
        ];
        for data in cases {
            let packed = deflate(&data);
            assert_eq!(inflate_fixed(&packed), data);
        }
    }

    #[test]
    fn compresses_repetitive_json() {
        let data = "{\"resourceMetrics\": []}, ".repeat(400);
        let packed = compress(data.as_bytes());
        assert!(
            packed.len() < data.len() / 5,
            "{} vs {}",
            packed.len(),
            data.len()
        );
        assert_eq!(&packed[..3], &[0x1f, 0x8b, 8]);
    }
}
