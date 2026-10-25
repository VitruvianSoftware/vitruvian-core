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

//! Pure-Rust port of the subset of CPython 3.12's `zipfile` module used to
//! inspect, read, and extract ZIP archives and to write simple stored or
//! deflated ZIP archives.

use std::cmp::Ordering;
use std::collections::BinaryHeap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// Default DOS epoch timestamp `(1980, 1, 1, 0, 0, 0)` used by `ZipInfo` and `ZipWriter`.
pub const DEFAULT_DATE_TIME: (u16, u8, u8, u8, u8, u8) = (1980, 1, 1, 0, 0, 0);

const ZIP_STORED: u16 = 0;
const ZIP_DEFLATED: u16 = 8;
const DEFAULT_VERSION: u8 = 20;
const MAX_EXTRACT_VERSION: u8 = 63;
const ZIP_MAX_COMMENT: usize = (1 << 16) - 1;

const MASK_ENCRYPTED: u16 = 1 << 0;
const MASK_COMPRESSED_PATCH: u16 = 1 << 5;
const MASK_STRONG_ENCRYPTION: u16 = 1 << 6;
const MASK_UTF_FILENAME: u16 = 1 << 11;

const STRING_END_ARCHIVE: &[u8; 4] = b"PK\x05\x06";
const SIZE_END_CENT_DIR: usize = 22;

const STRING_END_ARCHIVE64_LOCATOR: &[u8; 4] = b"PK\x06\x07";
const SIZE_END_CENT_DIR64_LOCATOR: usize = 20;

const STRING_END_ARCHIVE64: &[u8; 4] = b"PK\x06\x06";
const SIZE_END_CENT_DIR64: usize = 56;

const STRING_CENTRAL_DIR: &[u8; 4] = b"PK\x01\x02";
const SIZE_CENTRAL_DIR: usize = 46;

const STRING_FILE_HEADER: &[u8; 4] = b"PK\x03\x04";
const SIZE_FILE_HEADER: usize = 30;

// ---------------------------------------------------------------------------
// CRC-32
// ---------------------------------------------------------------------------

const CRC32_TABLE: [u32; 256] = {
    let mut table = [0u32; 256];
    let mut i = 0usize;
    while i < 256 {
        let mut crc = i as u32;
        let mut j = 0;
        while j < 8 {
            if (crc & 1) != 0 {
                crc = (crc >> 1) ^ 0xEDB8_8320;
            } else {
                crc >>= 1;
            }
            j += 1;
        }
        table[i] = crc;
        i += 1;
    }
    table
};

/// Computes the IEEE 802.3 / zlib / ZIP CRC-32 checksum of `data`.
pub fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &b in data {
        let idx = ((crc as u8) ^ b) as usize;
        crc = (crc >> 8) ^ CRC32_TABLE[idx];
    }
    !crc
}

// ---------------------------------------------------------------------------
// DEFLATE / INFLATE (RFC 1951)
// ---------------------------------------------------------------------------

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

const CL_ORDER: [usize; 19] = [
    16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
];

struct BitReader<'a> {
    data: &'a [u8],
    pos: usize,
    bit_buf: u32,
    bit_count: u8,
}

impl<'a> BitReader<'a> {
    fn new(data: &'a [u8]) -> Self {
        Self {
            data,
            pos: 0,
            bit_buf: 0,
            bit_count: 0,
        }
    }

    fn read_bits(&mut self, n: u8) -> Result<u32, String> {
        while self.bit_count < n {
            if self.pos >= self.data.len() {
                return Err("Truncated deflate stream".to_string());
            }
            self.bit_buf |= (self.data[self.pos] as u32) << self.bit_count;
            self.pos += 1;
            self.bit_count += 8;
        }
        let mask = if n == 32 { u32::MAX } else { (1u32 << n) - 1 };
        let val = self.bit_buf & mask;
        self.bit_buf >>= n;
        self.bit_count -= n;
        Ok(val)
    }

    fn align_to_byte(&mut self) {
        self.bit_buf = 0;
        self.bit_count = 0;
    }

    fn read_u16_le(&mut self) -> Result<u16, String> {
        if self.pos + 2 > self.data.len() {
            return Err("Truncated deflate stream in stored block header".to_string());
        }
        let lo = self.data[self.pos] as u16;
        let hi = self.data[self.pos + 1] as u16;
        self.pos += 2;
        Ok(lo | (hi << 8))
    }

    fn read_bytes(&mut self, len: usize) -> Result<&'a [u8], String> {
        if self.pos + len > self.data.len() {
            return Err("Truncated deflate stream in stored block data".to_string());
        }
        let slice = &self.data[self.pos..self.pos + len];
        self.pos += len;
        Ok(slice)
    }
}

struct HuffmanTree {
    /// Each element is `[child0, child1]`.
    /// `0` means unassigned, `> 0` is an internal node index, `< 0` is a leaf `-(sym as i32 + 1)`.
    nodes: Vec<[i32; 2]>,
}

impl HuffmanTree {
    fn from_lengths(lengths: &[u8]) -> Result<Self, String> {
        let mut bl_count = [0u32; 16];
        let mut max_len = 0usize;
        for &len in lengths {
            if len as usize > 15 {
                return Err("Code length exceeds 15".to_string());
            }
            if len > 0 {
                bl_count[len as usize] += 1;
                if (len as usize) > max_len {
                    max_len = len as usize;
                }
            }
        }
        if max_len == 0 {
            return Ok(Self { nodes: Vec::new() });
        }

        let mut left = 1i32;
        for &count in &bl_count[1..=15] {
            left <<= 1;
            left -= count as i32;
            if left < 0 {
                return Err("Over-subscribed Huffman tree".to_string());
            }
        }

        let mut next_code = [0u32; 16];
        let mut code = 0u32;
        for bits in 1..=15 {
            code = (code + bl_count[bits - 1]) << 1;
            next_code[bits] = code;
        }

        let mut nodes = vec![[0i32; 2]];
        for (sym, &len) in lengths.iter().enumerate() {
            if len == 0 {
                continue;
            }
            let l = len as usize;
            let cw = next_code[l];
            next_code[l] += 1;

            let mut cur = 0usize;
            for bit_pos in (0..l).rev() {
                let bit = ((cw >> bit_pos) & 1) as usize;
                if bit_pos == 0 {
                    if nodes[cur][bit] != 0 {
                        return Err("Duplicate Huffman code assignment".to_string());
                    }
                    nodes[cur][bit] = -(sym as i32 + 1);
                } else {
                    let next = nodes[cur][bit];
                    if next < 0 {
                        return Err("Prefix collision in Huffman tree".to_string());
                    }
                    if next == 0 {
                        let new_idx = nodes.len();
                        nodes.push([0, 0]);
                        nodes[cur][bit] = new_idx as i32;
                        cur = new_idx;
                    } else {
                        cur = next as usize;
                    }
                }
            }
        }

        Ok(Self { nodes })
    }

    fn decode(&self, reader: &mut BitReader<'_>) -> Result<u16, String> {
        if self.nodes.is_empty() {
            return Err("Attempted to decode from an empty Huffman tree".to_string());
        }
        let mut cur = 0usize;
        loop {
            let bit = reader.read_bits(1)? as usize;
            let next = self.nodes[cur][bit];
            if next < 0 {
                return Ok((-next - 1) as u16);
            }
            if next == 0 {
                return Err("Invalid Huffman code in deflate stream".to_string());
            }
            cur = next as usize;
        }
    }
}

fn fixed_trees() -> Result<(HuffmanTree, HuffmanTree), String> {
    let mut lit_lengths = [0u8; 288];
    for l in &mut lit_lengths[0..=143] {
        *l = 8;
    }
    for l in &mut lit_lengths[144..=255] {
        *l = 9;
    }
    for l in &mut lit_lengths[256..=279] {
        *l = 7;
    }
    for l in &mut lit_lengths[280..=287] {
        *l = 8;
    }
    let dist_lengths = [5u8; 32];
    Ok((
        HuffmanTree::from_lengths(&lit_lengths)?,
        HuffmanTree::from_lengths(&dist_lengths)?,
    ))
}

fn dynamic_trees(reader: &mut BitReader<'_>) -> Result<(HuffmanTree, HuffmanTree), String> {
    let hlit = reader.read_bits(5)? as usize + 257;
    let hdist = reader.read_bits(5)? as usize + 1;
    let hclen = reader.read_bits(4)? as usize + 4;
    if hlit > 286 || hdist > 30 {
        return Err("Invalid HLIT or HDIST in dynamic block header".to_string());
    }

    let mut cl_lengths = [0u8; 19];
    for i in 0..hclen {
        cl_lengths[CL_ORDER[i]] = reader.read_bits(3)? as u8;
    }
    let cl_tree = HuffmanTree::from_lengths(&cl_lengths)?;

    let total_codes = hlit + hdist;
    let mut lengths = Vec::with_capacity(total_codes);
    while lengths.len() < total_codes {
        let sym = cl_tree.decode(reader)?;
        match sym {
            0..=15 => lengths.push(sym as u8),
            16 => {
                let prev = *lengths
                    .last()
                    .ok_or_else(|| "Repeat code 16 with no previous code length".to_string())?;
                let repeat = reader.read_bits(2)? as usize + 3;
                if lengths.len() + repeat > total_codes {
                    return Err("Code length repeat exceeds table size".to_string());
                }
                lengths.resize(lengths.len() + repeat, prev);
            }
            17 => {
                let repeat = reader.read_bits(3)? as usize + 3;
                if lengths.len() + repeat > total_codes {
                    return Err("Code length zero run (17) exceeds table size".to_string());
                }
                lengths.resize(lengths.len() + repeat, 0);
            }
            18 => {
                let repeat = reader.read_bits(7)? as usize + 11;
                if lengths.len() + repeat > total_codes {
                    return Err("Code length zero run (18) exceeds table size".to_string());
                }
                lengths.resize(lengths.len() + repeat, 0);
            }
            _ => return Err("Invalid code length symbol".to_string()),
        }
    }

    let lit_len_slice = &lengths[..hlit];
    let dist_slice = &lengths[hlit..];
    if lit_len_slice.get(256).copied().unwrap_or(0) == 0 {
        return Err("Dynamic Huffman block missing end-of-block symbol".to_string());
    }

    let lit_tree = HuffmanTree::from_lengths(lit_len_slice)?;
    let dist_tree = HuffmanTree::from_lengths(dist_slice)?;
    Ok((lit_tree, dist_tree))
}

fn decode_huffman_block(
    reader: &mut BitReader<'_>,
    lit_tree: &HuffmanTree,
    dist_tree: &HuffmanTree,
    out: &mut Vec<u8>,
) -> Result<(), String> {
    loop {
        let sym = lit_tree.decode(reader)?;
        if sym < 256 {
            out.push(sym as u8);
        } else if sym == 256 {
            break;
        } else if sym <= 285 {
            let len_idx = (sym - 257) as usize;
            let extra_bits = LEN_EXTRA[len_idx];
            let extra = if extra_bits > 0 {
                reader.read_bits(extra_bits)? as usize
            } else {
                0
            };
            let length = LEN_BASE[len_idx] as usize + extra;

            let dist_sym = dist_tree.decode(reader)? as usize;
            if dist_sym >= 30 {
                return Err("Invalid distance symbol in deflate stream".to_string());
            }
            let dist_eb = DIST_EXTRA[dist_sym];
            let dist_extra = if dist_eb > 0 {
                reader.read_bits(dist_eb)? as usize
            } else {
                0
            };
            let distance = DIST_BASE[dist_sym] as usize + dist_extra;
            if distance > out.len() {
                return Err("Distance exceeds output buffer in deflate stream".to_string());
            }

            let start = out.len() - distance;
            for i in 0..length {
                let b = out[start + i];
                out.push(b);
            }
        } else {
            return Err("Invalid literal/length symbol in deflate stream".to_string());
        }
    }
    Ok(())
}

/// Decompresses a raw DEFLATE stream (RFC 1951), supporting stored, fixed
/// Huffman, and dynamic Huffman blocks.
pub fn inflate(data: &[u8]) -> Result<Vec<u8>, String> {
    let mut reader = BitReader::new(data);
    let mut out = Vec::new();
    loop {
        let bfinal = reader.read_bits(1)?;
        let btype = reader.read_bits(2)?;
        match btype {
            0 => {
                reader.align_to_byte();
                let len = reader.read_u16_le()?;
                let nlen = reader.read_u16_le()?;
                if len != !nlen {
                    return Err("Corrupt deflate stream: stored block length mismatch".to_string());
                }
                let slice = reader.read_bytes(len as usize)?;
                out.extend_from_slice(slice);
            }
            1 => {
                let (lit_tree, dist_tree) = fixed_trees()?;
                decode_huffman_block(&mut reader, &lit_tree, &dist_tree, &mut out)?;
            }
            2 => {
                let (lit_tree, dist_tree) = dynamic_trees(&mut reader)?;
                decode_huffman_block(&mut reader, &lit_tree, &dist_tree, &mut out)?;
            }
            _ => {
                return Err("Invalid deflate block type 3".to_string());
            }
        }
        if bfinal == 1 {
            break;
        }
    }
    Ok(out)
}

// ---------------------------------------------------------------------------
// DEFLATE Encoder (LZ77 + Fixed / Dynamic Huffman)
// ---------------------------------------------------------------------------

#[derive(Clone, Copy)]
enum Token {
    Lit(u8),
    Match { len: u16, dist: u16 },
}

struct BitWriter {
    buf: Vec<u8>,
    bit_buf: u32,
    bit_count: u8,
}

impl BitWriter {
    fn new() -> Self {
        Self {
            buf: Vec::new(),
            bit_buf: 0,
            bit_count: 0,
        }
    }

    fn write_bits(&mut self, val: u32, n: u8) {
        self.bit_buf |= (val & ((1u32 << n) - 1)) << self.bit_count;
        self.bit_count += n;
        while self.bit_count >= 8 {
            self.buf.push(self.bit_buf as u8);
            self.bit_buf >>= 8;
            self.bit_count -= 8;
        }
    }

    fn finish(mut self) -> Vec<u8> {
        if self.bit_count > 0 {
            self.buf.push(self.bit_buf as u8);
        }
        self.buf
    }
}

fn reverse_bits(mut code: u16, len: u8) -> u16 {
    let mut rev = 0u16;
    for _ in 0..len {
        rev = (rev << 1) | (code & 1);
        code >>= 1;
    }
    rev
}

fn canonical_codes(lengths: &[u8]) -> Vec<u16> {
    let mut bl_count = [0u16; 16];
    for &l in lengths {
        if l > 0 {
            bl_count[l as usize] += 1;
        }
    }
    let mut next_code = [0u16; 16];
    let mut code = 0u16;
    for bits in 1..=15 {
        code = (code + bl_count[bits - 1]) << 1;
        next_code[bits] = code;
    }
    let mut codes = vec![0u16; lengths.len()];
    for (sym, &l) in lengths.iter().enumerate() {
        if l > 0 {
            let cw = next_code[l as usize];
            next_code[l as usize] += 1;
            codes[sym] = reverse_bits(cw, l);
        }
    }
    codes
}

fn encode_length(len: u16) -> (usize, u8, u16) {
    let mut idx = 0usize;
    for (i, &base) in LEN_BASE.iter().enumerate() {
        if len >= base {
            idx = i;
        } else {
            break;
        }
    }
    let eb = LEN_EXTRA[idx];
    let ev = len - LEN_BASE[idx];
    (257 + idx, eb, ev)
}

fn encode_distance(dist: u16) -> (usize, u8, u16) {
    let mut idx = 0usize;
    for (i, &base) in DIST_BASE.iter().enumerate() {
        if dist >= base {
            idx = i;
        } else {
            break;
        }
    }
    let eb = DIST_EXTRA[idx];
    let ev = dist - DIST_BASE[idx];
    (idx, eb, ev)
}

fn lz77_tokenize(data: &[u8]) -> Vec<Token> {
    const WINDOW_SIZE: usize = 32768;
    const MIN_MATCH: usize = 3;
    const MAX_MATCH: usize = 258;
    const HASH_BITS: usize = 15;
    const HASH_SIZE: usize = 1 << HASH_BITS;
    const MAX_CHAIN: usize = 96;

    let n = data.len();
    if n == 0 {
        return Vec::new();
    }

    let mut head = vec![-1i32; HASH_SIZE];
    let mut prev = vec![-1i32; n];
    let mut tokens = Vec::with_capacity(n / 2 + 16);

    let hash3 = |pos: usize| -> usize {
        (((data[pos] as usize) << 10) ^ ((data[pos + 1] as usize) << 5) ^ (data[pos + 2] as usize))
            & (HASH_SIZE - 1)
    };

    let find_match = |pos: usize, head: &[i32], prev: &[i32]| -> (usize, usize) {
        if pos + MIN_MATCH > n {
            return (0, 0);
        }
        let h = hash3(pos);
        let mut cur = head[h];
        let max_len = MAX_MATCH.min(n - pos);
        let min_pos = pos.saturating_sub(WINDOW_SIZE);
        let mut best_len = 0usize;
        let mut best_dist = 0usize;
        let mut chain = 0usize;

        while cur >= 0 && (cur as usize) >= min_pos && chain < MAX_CHAIN {
            let cand = cur as usize;
            if data[cand + best_len] == data[pos + best_len]
                && data[cand] == data[pos]
                && data[cand + 1] == data[pos + 1]
                && data[cand + 2] == data[pos + 2]
            {
                let mut l = 3usize;
                while l < max_len && data[cand + l] == data[pos + l] {
                    l += 1;
                }
                if l > best_len {
                    best_len = l;
                    best_dist = pos - cand;
                    if best_len == max_len {
                        break;
                    }
                }
            }
            cur = prev[cand];
            chain += 1;
        }
        (best_len, best_dist)
    };

    let mut pos = 0usize;
    while pos < n {
        let (best_len, best_dist) = find_match(pos, &head, &prev);
        if pos + MIN_MATCH <= n {
            let h = hash3(pos);
            prev[pos] = head[h];
            head[h] = pos as i32;
        }

        if best_len >= MIN_MATCH {
            // Simple 1-step lazy match check for better compression
            if best_len < 32 && pos + 1 + MIN_MATCH <= n {
                let (next_len, _) = find_match(pos + 1, &head, &prev);
                if next_len > best_len + 1 {
                    tokens.push(Token::Lit(data[pos]));
                    pos += 1;
                    continue;
                }
            }

            tokens.push(Token::Match {
                len: best_len as u16,
                dist: best_dist as u16,
            });
            for step in 1..best_len {
                let p = pos + step;
                if p + MIN_MATCH <= n {
                    let h = hash3(p);
                    prev[p] = head[h];
                    head[h] = p as i32;
                }
            }
            pos += best_len;
        } else {
            tokens.push(Token::Lit(data[pos]));
            pos += 1;
        }
    }

    tokens
}

#[derive(Eq, PartialEq)]
struct HeapNode {
    freq: u64,
    depth: u8,
    idx: usize,
}

impl Ord for HeapNode {
    fn cmp(&self, other: &Self) -> Ordering {
        other
            .freq
            .cmp(&self.freq)
            .then_with(|| other.depth.cmp(&self.depth))
            .then_with(|| other.idx.cmp(&self.idx))
    }
}

impl PartialOrd for HeapNode {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

fn build_code_lengths(freqs: &[u64], max_bits: u8) -> Vec<u8> {
    let mut lengths = vec![0u8; freqs.len()];
    let active: Vec<(usize, u64)> = freqs
        .iter()
        .copied()
        .enumerate()
        .filter(|&(_, f)| f > 0)
        .collect();

    if active.is_empty() {
        if lengths.len() >= 2 {
            lengths[0] = 1;
            lengths[1] = 1;
        } else if !lengths.is_empty() {
            lengths[0] = 1;
        }
        return lengths;
    }

    if active.len() == 1 {
        let s0 = active[0].0;
        lengths[s0] = 1;
        if lengths.len() >= 2 {
            let s1 = if s0 == 0 { 1 } else { 0 };
            lengths[s1] = 1;
        }
        return lengths;
    }

    let num_active = active.len();
    let mut children: Vec<Option<(usize, usize)>> = vec![None; 2 * num_active];
    let mut heap = BinaryHeap::with_capacity(num_active);
    for (i, &(_, freq)) in active.iter().enumerate() {
        heap.push(HeapNode {
            freq,
            depth: 0,
            idx: i,
        });
    }

    let mut next_node = num_active;
    while heap.len() > 1 {
        let a = heap.pop().unwrap();
        let b = heap.pop().unwrap();
        children[next_node] = Some((a.idx, b.idx));
        heap.push(HeapNode {
            freq: a.freq + b.freq,
            depth: a.depth.max(b.depth) + 1,
            idx: next_node,
        });
        next_node += 1;
    }

    let root = heap.pop().unwrap().idx;
    let mut node_depths = vec![0u8; next_node];
    let mut stack = vec![root];
    while let Some(u) = stack.pop() {
        if let Some((l, r)) = children[u] {
            node_depths[l] = node_depths[u] + 1;
            node_depths[r] = node_depths[u] + 1;
            stack.push(l);
            stack.push(r);
        }
    }

    let mut raw_lens: Vec<(usize, u64, u8)> = active
        .iter()
        .enumerate()
        .map(|(i, &(sym, freq))| (sym, freq, node_depths[i]))
        .collect();

    if raw_lens.iter().any(|&(_, _, l)| l > max_bits) {
        // Sort by frequency ascending (lowest frequency first)
        raw_lens.sort_by(|a, b| a.1.cmp(&b.1).then_with(|| a.0.cmp(&b.0)));
        for item in &mut raw_lens {
            if item.2 > max_bits {
                item.2 = max_bits;
            }
        }
        let limit = 1u32 << max_bits;
        let mut kraft: u32 = raw_lens
            .iter()
            .map(|&(_, _, l)| 1u32 << (max_bits - l))
            .sum();

        while kraft > limit {
            for item in &mut raw_lens {
                if item.2 < max_bits {
                    let delta = 1u32 << (max_bits - item.2 - 1);
                    item.2 += 1;
                    kraft -= delta;
                    if kraft <= limit {
                        break;
                    }
                }
            }
        }

        while kraft < limit {
            let mut changed = false;
            for item in raw_lens.iter_mut().rev() {
                if item.2 > 1 {
                    let delta = 1u32 << (max_bits - item.2);
                    if kraft + delta <= limit {
                        item.2 -= 1;
                        kraft += delta;
                        changed = true;
                        if kraft == limit {
                            break;
                        }
                    }
                }
            }
            if !changed {
                break;
            }
        }
    }

    for (sym, _, l) in raw_lens {
        lengths[sym] = l;
    }
    lengths
}

fn write_tokens(
    writer: &mut BitWriter,
    tokens: &[Token],
    lit_lengths: &[u8],
    lit_codes: &[u16],
    dist_lengths: &[u8],
    dist_codes: &[u16],
) {
    for &tok in tokens {
        match tok {
            Token::Lit(b) => {
                let s = b as usize;
                writer.write_bits(lit_codes[s] as u32, lit_lengths[s]);
            }
            Token::Match { len, dist } => {
                let (lsym, leb, lev) = encode_length(len);
                writer.write_bits(lit_codes[lsym] as u32, lit_lengths[lsym]);
                if leb > 0 {
                    writer.write_bits(lev as u32, leb);
                }
                let (dsym, deb, dev) = encode_distance(dist);
                writer.write_bits(dist_codes[dsym] as u32, dist_lengths[dsym]);
                if deb > 0 {
                    writer.write_bits(dev as u32, deb);
                }
            }
        }
    }
    writer.write_bits(lit_codes[256] as u32, lit_lengths[256]);
}

fn encode_fixed_block(tokens: &[Token]) -> Vec<u8> {
    let mut lit_lengths = [0u8; 288];
    for l in &mut lit_lengths[0..=143] {
        *l = 8;
    }
    for l in &mut lit_lengths[144..=255] {
        *l = 9;
    }
    for l in &mut lit_lengths[256..=279] {
        *l = 7;
    }
    for l in &mut lit_lengths[280..=287] {
        *l = 8;
    }
    let dist_lengths = [5u8; 32];
    let lit_codes = canonical_codes(&lit_lengths);
    let dist_codes = canonical_codes(&dist_lengths);

    let mut writer = BitWriter::new();
    writer.write_bits(1, 1); // BFINAL = 1
    writer.write_bits(1, 2); // BTYPE = 1 (fixed)
    write_tokens(
        &mut writer,
        tokens,
        &lit_lengths,
        &lit_codes,
        &dist_lengths,
        &dist_codes,
    );
    writer.finish()
}

fn encode_dynamic_block(tokens: &[Token]) -> Vec<u8> {
    let mut lit_freqs = [0u64; 286];
    let mut dist_freqs = [0u64; 30];
    lit_freqs[256] = 1; // EOB

    for &tok in tokens {
        match tok {
            Token::Lit(b) => lit_freqs[b as usize] += 1,
            Token::Match { len, dist } => {
                let (lsym, _, _) = encode_length(len);
                let (dsym, _, _) = encode_distance(dist);
                lit_freqs[lsym] += 1;
                dist_freqs[dsym] += 1;
            }
        }
    }

    let lit_lengths = build_code_lengths(&lit_freqs, 15);
    let dist_lengths = build_code_lengths(&dist_freqs, 15);

    let hlit = (257..=286)
        .rev()
        .find(|&n| lit_lengths[n - 1] != 0)
        .unwrap_or(257);
    let hdist = (1..=30)
        .rev()
        .find(|&n| dist_lengths[n - 1] != 0)
        .unwrap_or(1);

    let mut combined = Vec::with_capacity(hlit + hdist);
    combined.extend_from_slice(&lit_lengths[..hlit]);
    combined.extend_from_slice(&dist_lengths[..hdist]);

    // Run-length encode combined lengths using symbols 0..=18
    let mut rle: Vec<(u8, u8, u16)> = Vec::new();
    let mut i = 0usize;
    while i < combined.len() {
        let v = combined[i];
        let mut run = 1usize;
        while i + run < combined.len() && combined[i + run] == v {
            run += 1;
        }
        i += run;
        if v == 0 {
            while run >= 11 {
                let n = run.min(138);
                rle.push((18, 7, (n - 11) as u16));
                run -= n;
            }
            if run >= 3 {
                rle.push((17, 3, (run - 3) as u16));
                run = 0;
            }
            while run > 0 {
                rle.push((0, 0, 0));
                run -= 1;
            }
        } else {
            rle.push((v, 0, 0));
            run -= 1;
            while run >= 3 {
                let n = run.min(6);
                rle.push((16, 2, (n - 3) as u16));
                run -= n;
            }
            while run > 0 {
                rle.push((v, 0, 0));
                run -= 1;
            }
        }
    }

    let mut cl_freqs = [0u64; 19];
    for &(sym, _, _) in &rle {
        cl_freqs[sym as usize] += 1;
    }
    let cl_lengths = build_code_lengths(&cl_freqs, 7);
    let cl_codes = canonical_codes(&cl_lengths);

    let hclen = (4..=19)
        .rev()
        .find(|&n| cl_lengths[CL_ORDER[n - 1]] != 0)
        .unwrap_or(4);

    let lit_codes = canonical_codes(&lit_lengths);
    let dist_codes = canonical_codes(&dist_lengths);

    let mut writer = BitWriter::new();
    writer.write_bits(1, 1); // BFINAL = 1
    writer.write_bits(2, 2); // BTYPE = 2 (dynamic)
    writer.write_bits((hlit - 257) as u32, 5);
    writer.write_bits((hdist - 1) as u32, 5);
    writer.write_bits((hclen - 4) as u32, 4);

    for &ord in &CL_ORDER[..hclen] {
        writer.write_bits(cl_lengths[ord] as u32, 3);
    }

    for &(sym, eb, ev) in &rle {
        let s = sym as usize;
        writer.write_bits(cl_codes[s] as u32, cl_lengths[s]);
        if eb > 0 {
            writer.write_bits(ev as u32, eb);
        }
    }

    write_tokens(
        &mut writer,
        tokens,
        &lit_lengths,
        &lit_codes,
        &dist_lengths,
        &dist_codes,
    );
    writer.finish()
}

/// Compresses `data` into a raw DEFLATE stream (RFC 1951) using LZ77 with a
/// 32 KiB sliding window and hash chains followed by Huffman coding.
pub fn deflate(data: &[u8]) -> Vec<u8> {
    let tokens = lz77_tokenize(data);
    let fixed = encode_fixed_block(&tokens);
    if tokens.len() < 32 {
        return fixed;
    }
    let dynamic = encode_dynamic_block(&tokens);
    if dynamic.len() <= fixed.len() {
        dynamic
    } else {
        fixed
    }
}

// ---------------------------------------------------------------------------
// CP437 and Python repr helpers
// ---------------------------------------------------------------------------

const CP437_HIGH: [char; 128] = [
    '\u{00C7}', '\u{00FC}', '\u{00E9}', '\u{00E2}', '\u{00E4}', '\u{00E0}', '\u{00E5}', '\u{00E7}',
    '\u{00EA}', '\u{00EB}', '\u{00E8}', '\u{00EF}', '\u{00EE}', '\u{00EC}', '\u{00C4}', '\u{00C5}',
    '\u{00C9}', '\u{00E6}', '\u{00C6}', '\u{00F4}', '\u{00F6}', '\u{00F2}', '\u{00FB}', '\u{00F9}',
    '\u{00FF}', '\u{00D6}', '\u{00DC}', '\u{00A2}', '\u{00A3}', '\u{00A5}', '\u{20A7}', '\u{0192}',
    '\u{00E1}', '\u{00ED}', '\u{00F3}', '\u{00FA}', '\u{00F1}', '\u{00D1}', '\u{00AA}', '\u{00BA}',
    '\u{00BF}', '\u{2310}', '\u{00AC}', '\u{00BD}', '\u{00BC}', '\u{00A1}', '\u{00AB}', '\u{00BB}',
    '\u{2591}', '\u{2592}', '\u{2593}', '\u{2502}', '\u{2524}', '\u{2561}', '\u{2562}', '\u{2556}',
    '\u{2555}', '\u{2563}', '\u{2551}', '\u{2557}', '\u{255D}', '\u{255C}', '\u{255B}', '\u{2510}',
    '\u{2514}', '\u{2534}', '\u{252C}', '\u{251C}', '\u{2500}', '\u{253C}', '\u{255E}', '\u{255F}',
    '\u{255A}', '\u{2554}', '\u{2569}', '\u{2566}', '\u{2560}', '\u{2550}', '\u{256C}', '\u{2567}',
    '\u{2568}', '\u{2564}', '\u{2565}', '\u{2559}', '\u{2558}', '\u{2552}', '\u{2553}', '\u{256B}',
    '\u{256A}', '\u{2518}', '\u{250C}', '\u{2588}', '\u{2584}', '\u{258C}', '\u{2590}', '\u{2580}',
    '\u{03B1}', '\u{00DF}', '\u{0393}', '\u{03C0}', '\u{03A3}', '\u{03C3}', '\u{00B5}', '\u{03C4}',
    '\u{03A6}', '\u{0398}', '\u{03A9}', '\u{03B4}', '\u{221E}', '\u{03C6}', '\u{03B5}', '\u{2229}',
    '\u{2261}', '\u{00B1}', '\u{2265}', '\u{2264}', '\u{2320}', '\u{2321}', '\u{00F7}', '\u{2248}',
    '\u{00B0}', '\u{2219}', '\u{00B7}', '\u{221A}', '\u{207F}', '\u{00B2}', '\u{25A0}', '\u{00A0}',
];

fn decode_cp437(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len());
    for &b in bytes {
        if b < 0x80 {
            s.push(b as char);
        } else {
            s.push(CP437_HIGH[(b - 0x80) as usize]);
        }
    }
    s
}

fn sanitize_filename(name: &str) -> String {
    match name.find('\0') {
        Some(idx) => name[..idx].to_string(),
        None => name.to_string(),
    }
}

fn py_str_repr(s: &str) -> String {
    let use_double = s.contains('\'') && !s.contains('"');
    let quote = if use_double { '"' } else { '\'' };
    let mut out = String::with_capacity(s.len() + 2);
    out.push(quote);
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '\t' => out.push_str("\\t"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            _ if c == quote => {
                out.push('\\');
                out.push(quote);
            }
            _ if (c as u32) < 0x20 || (0x7f..=0x9f).contains(&(c as u32)) => {
                out.push_str(&format!("\\x{:02x}", c as u32));
            }
            _ => out.push(c),
        }
    }
    out.push(quote);
    out
}

fn read_u16_le(b: &[u8], off: usize) -> u16 {
    u16::from_le_bytes([b[off], b[off + 1]])
}

fn read_u32_le(b: &[u8], off: usize) -> u32 {
    u32::from_le_bytes([b[off], b[off + 1], b[off + 2], b[off + 3]])
}

fn read_u64_le(b: &[u8], off: usize) -> u64 {
    u64::from_le_bytes([
        b[off],
        b[off + 1],
        b[off + 2],
        b[off + 3],
        b[off + 4],
        b[off + 5],
        b[off + 6],
        b[off + 7],
    ])
}

// ---------------------------------------------------------------------------
// ZipInfo
// ---------------------------------------------------------------------------

/// Metadata for a single member in a ZIP archive, matching Python's `zipfile.ZipInfo`.
#[derive(Clone, Debug, PartialEq)]
pub struct ZipInfo {
    pub filename: String,
    pub orig_filename: String,
    pub create_system: u8,
    pub create_version: u8,
    pub extract_version: u8,
    pub reserved: u8,
    pub flag_bits: u16,
    pub compress_type: u16,
    pub date_time: (u16, u8, u8, u8, u8, u8),
    pub crc: u32,
    pub compress_size: u64,
    pub file_size: u64,
    pub internal_attr: u16,
    pub external_attr: u32,
    pub header_offset: u64,
    pub extra: Vec<u8>,
    pub comment: Vec<u8>,
}

impl ZipInfo {
    /// Returns `true` if this archive member is a directory (`filename` ends with `'/'`).
    pub fn is_dir(&self) -> bool {
        self.filename.ends_with('/')
    }

    fn decode_extra(&mut self, filename_crc: u32) -> Result<(), String> {
        let mut extra: &[u8] = &self.extra;
        while extra.len() >= 4 {
            let tp = read_u16_le(extra, 0);
            let ln = read_u16_le(extra, 2) as usize;
            if ln + 4 > extra.len() {
                return Err(format!("Corrupt extra field {:04x} (size={})", tp, ln));
            }
            let mut data = &extra[4..ln + 4];
            if tp == 0x0001 {
                if self.file_size == 0xFFFF_FFFF_FFFF_FFFF || self.file_size == 0xFFFF_FFFF {
                    if data.len() < 8 {
                        return Err("Corrupt zip64 extra field. File size not found.".to_string());
                    }
                    self.file_size = read_u64_le(data, 0);
                    data = &data[8..];
                }
                if self.compress_size == 0xFFFF_FFFF {
                    if data.len() < 8 {
                        return Err(
                            "Corrupt zip64 extra field. Compress size not found.".to_string()
                        );
                    }
                    self.compress_size = read_u64_le(data, 0);
                    data = &data[8..];
                }
                if self.header_offset == 0xFFFF_FFFF {
                    if data.len() < 8 {
                        return Err(
                            "Corrupt zip64 extra field. Header offset not found.".to_string()
                        );
                    }
                    self.header_offset = read_u64_le(data, 0);
                }
            } else if tp == 0x7075 {
                if data.len() < 5 {
                    return Err("Corrupt unicode path extra field (0x7075)".to_string());
                }
                let up_version = data[0];
                let up_name_crc = read_u32_le(data, 1);
                if up_version == 1 && up_name_crc == filename_crc {
                    let up_unicode_name = std::str::from_utf8(&data[5..]).map_err(|_| {
                        "Corrupt unicode path extra field (0x7075): invalid utf-8 bytes".to_string()
                    })?;
                    if !up_unicode_name.is_empty() {
                        self.filename = sanitize_filename(up_unicode_name);
                    }
                }
            }
            extra = &extra[ln + 4..];
        }
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// End of Central Directory parsing
// ---------------------------------------------------------------------------

struct EndRec {
    size_cd: u64,
    offset_cd: u64,
    #[allow(dead_code)]
    comment: Vec<u8>,
    location: u64,
}

fn end_rec_data64(bytes: &[u8], offset_in: usize, mut endrec: EndRec) -> Result<EndRec, String> {
    if offset_in < SIZE_END_CENT_DIR64_LOCATOR {
        return Ok(endrec);
    }
    let mut offset = offset_in - SIZE_END_CENT_DIR64_LOCATOR;
    let loc_data = &bytes[offset..offset + SIZE_END_CENT_DIR64_LOCATOR];
    if &loc_data[0..4] != STRING_END_ARCHIVE64_LOCATOR {
        return Ok(endrec);
    }
    let diskno = read_u32_le(loc_data, 4);
    let reloff = read_u64_le(loc_data, 8);
    let disks = read_u32_le(loc_data, 16);
    if diskno != 0 || disks > 1 {
        return Err("zipfiles that span multiple disks are not supported".to_string());
    }

    if offset < SIZE_END_CENT_DIR64 || reloff > (offset - SIZE_END_CENT_DIR64) as u64 {
        return Err("Corrupt zip64 end of central directory locator".to_string());
    }
    offset -= SIZE_END_CENT_DIR64;

    let reloff_usize = reloff as usize;
    let mut extrasz = (offset as u64) - reloff;
    let mut data = &bytes[reloff_usize..reloff_usize + SIZE_END_CENT_DIR64];
    if !data.starts_with(STRING_END_ARCHIVE64) && reloff != offset as u64 {
        extrasz = 0;
        data = &bytes[offset..offset + SIZE_END_CENT_DIR64];
    }
    if !data.starts_with(STRING_END_ARCHIVE64) {
        return Err("Zip64 end of central directory record not found".to_string());
    }

    let sz = read_u64_le(data, 4);
    let dirsize = read_u64_le(data, 40);
    let diroffset = read_u64_le(data, 48);

    if diroffset.checked_add(dirsize) != Some(reloff)
        || sz.checked_add(12) != Some((SIZE_END_CENT_DIR64 as u64) + extrasz)
    {
        return Err("Corrupt zip64 end of central directory record".to_string());
    }

    endrec.size_cd = dirsize;
    endrec.offset_cd = diroffset;
    endrec.location = (offset as u64) - extrasz;
    Ok(endrec)
}

fn end_rec_data(bytes: &[u8]) -> Result<EndRec, String> {
    let filesize = bytes.len();
    if filesize < SIZE_END_CENT_DIR {
        return Err("File is not a zip file".to_string());
    }

    let eocd_off = filesize - SIZE_END_CENT_DIR;
    let data = &bytes[eocd_off..];
    if &data[0..4] == STRING_END_ARCHIVE && data[20..22] == [0, 0] {
        let size_cd = read_u32_le(data, 12) as u64;
        let offset_cd = read_u32_le(data, 16) as u64;
        let endrec = EndRec {
            size_cd,
            offset_cd,
            comment: Vec::new(),
            location: eocd_off as u64,
        };
        return end_rec_data64(bytes, eocd_off, endrec);
    }

    let max_comment_start = filesize.saturating_sub(ZIP_MAX_COMMENT + SIZE_END_CENT_DIR);
    let window = &bytes[max_comment_start..];
    let mut found_start: Option<usize> = None;
    if window.len() >= 4 {
        for i in (0..=window.len() - 4).rev() {
            if &window[i..i + 4] == STRING_END_ARCHIVE {
                found_start = Some(i);
                break;
            }
        }
    }

    if let Some(start) = found_start {
        if start + SIZE_END_CENT_DIR > window.len() {
            return Err("File is not a zip file".to_string());
        }
        let rec = &window[start..start + SIZE_END_CENT_DIR];
        let size_cd = read_u32_le(rec, 12) as u64;
        let offset_cd = read_u32_le(rec, 16) as u64;
        let comment_size = read_u16_le(rec, 20) as usize;
        let comment_start = start + SIZE_END_CENT_DIR;
        let comment_end = (comment_start + comment_size).min(window.len());
        let comment = window[comment_start..comment_end].to_vec();
        let loc = max_comment_start + start;
        let endrec = EndRec {
            size_cd,
            offset_cd,
            comment,
            location: loc as u64,
        };
        return end_rec_data64(bytes, loc, endrec);
    }

    Err("File is not a zip file".to_string())
}

// ---------------------------------------------------------------------------
// ZipFile
// ---------------------------------------------------------------------------

/// A ZIP archive reader backed by in-memory bytes, matching CPython 3.12's `zipfile.ZipFile`.
pub struct ZipFile {
    bytes: Vec<u8>,
    entries: Vec<ZipInfo>,
    end_offsets: Vec<u64>,
    start_dir: u64,
}

impl ZipFile {
    /// Parses the central directory of the ZIP archive in `bytes`.
    pub fn new(bytes: Vec<u8>) -> Result<ZipFile, String> {
        let endrec = end_rec_data(&bytes)?;
        let size_cd = endrec.size_cd as i128;
        let offset_cd = endrec.offset_cd as i128;
        let location = endrec.location as i128;
        let concat = location - size_cd - offset_cd;
        let start_dir_i128 = offset_cd + concat;
        if start_dir_i128 < 0 {
            return Err("Bad offset for central directory".to_string());
        }
        let start_dir = start_dir_i128 as u64;
        let start_usize = start_dir as usize;
        let cd_data: &[u8] = if start_usize >= bytes.len() {
            &[]
        } else {
            let end = start_usize
                .saturating_add(endrec.size_cd as usize)
                .min(bytes.len());
            &bytes[start_usize..end]
        };

        let mut entries = Vec::new();
        let mut total = 0usize;
        let size_cd_usize = endrec.size_cd as usize;

        while total < size_cd_usize {
            if total + SIZE_CENTRAL_DIR > cd_data.len() {
                return Err("Truncated central directory".to_string());
            }
            let centdir = &cd_data[total..total + SIZE_CENTRAL_DIR];
            if &centdir[0..4] != STRING_CENTRAL_DIR {
                return Err("Bad magic number for central directory".to_string());
            }

            let create_version = centdir[4];
            let create_system = centdir[5];
            let extract_version = centdir[6];
            let reserved = centdir[7];
            let flag_bits = read_u16_le(centdir, 8);
            let compress_type = read_u16_le(centdir, 10);
            let t = read_u16_le(centdir, 12);
            let d = read_u16_le(centdir, 14);
            let crc = read_u32_le(centdir, 16);
            let compress_size = read_u32_le(centdir, 20) as u64;
            let file_size = read_u32_le(centdir, 24) as u64;
            let fname_len = read_u16_le(centdir, 28) as usize;
            let extra_len = read_u16_le(centdir, 30) as usize;
            let comment_len = read_u16_le(centdir, 32) as usize;
            let internal_attr = read_u16_le(centdir, 36);
            let external_attr = read_u32_le(centdir, 38);
            let header_offset = read_u32_le(centdir, 42) as u64;

            let mut cur = total + SIZE_CENTRAL_DIR;
            let fname_end = (cur + fname_len).min(cd_data.len());
            let filename_bytes = &cd_data[cur..fname_end];
            cur = fname_end;

            let orig_filename_crc = crc32(filename_bytes);
            let orig_filename = if (flag_bits & MASK_UTF_FILENAME) != 0 {
                std::str::from_utf8(filename_bytes)
                    .map_err(|e| format!("UnicodeDecodeError: {e}"))?
                    .to_string()
            } else {
                decode_cp437(filename_bytes)
            };
            let filename = sanitize_filename(&orig_filename);

            let extra_end = (cur + extra_len).min(cd_data.len());
            let extra = cd_data[cur..extra_end].to_vec();
            cur = extra_end;

            let comment_end = (cur + comment_len).min(cd_data.len());
            let comment = cd_data[cur..comment_end].to_vec();

            if extract_version > MAX_EXTRACT_VERSION {
                return Err(format!(
                    "NotImplementedError: zip file version {:.1}",
                    (extract_version as f64) / 10.0
                ));
            }

            let date_time = (
                (d >> 9) + 1980,
                ((d >> 5) & 0xF) as u8,
                (d & 0x1F) as u8,
                (t >> 11) as u8,
                ((t >> 5) & 0x3F) as u8,
                ((t & 0x1F) * 2) as u8,
            );

            let mut info = ZipInfo {
                filename,
                orig_filename,
                create_system,
                create_version,
                extract_version,
                reserved,
                flag_bits,
                compress_type,
                date_time,
                crc,
                compress_size,
                file_size,
                internal_attr,
                external_attr,
                header_offset,
                extra,
                comment,
            };

            info.decode_extra(orig_filename_crc)?;
            let adj_header_offset = (info.header_offset as i128) + concat;
            if adj_header_offset < 0 {
                info.header_offset = u64::MAX;
            } else {
                info.header_offset = adj_header_offset as u64;
            }

            entries.push(info);
            total += SIZE_CENTRAL_DIR + fname_len + extra_len + comment_len;
        }

        let mut sorted_indices: Vec<usize> = (0..entries.len()).collect();
        sorted_indices.sort_by_key(|&i| entries[i].header_offset);
        let mut end_offsets = vec![0u64; entries.len()];
        let mut end_offset = start_dir;
        for &i in sorted_indices.iter().rev() {
            end_offsets[i] = end_offset;
            end_offset = entries[i].header_offset;
        }

        Ok(ZipFile {
            bytes,
            entries,
            end_offsets,
            start_dir,
        })
    }

    /// Returns the archive members in central-directory order.
    pub fn infolist(&self) -> &[ZipInfo] {
        &self.entries
    }

    /// Returns the list of member filenames in central-directory order.
    pub fn namelist(&self) -> Vec<String> {
        self.entries.iter().map(|e| e.filename.clone()).collect()
    }

    /// Returns the last `ZipInfo` entry with the given `name`, matching Python's `NameToInfo`.
    pub fn getinfo(&self, name: &str) -> Option<&ZipInfo> {
        self.entries.iter().rev().find(|e| e.filename == name)
    }

    fn end_offset_for(&self, info: &ZipInfo) -> Option<u64> {
        for (i, entry) in self.entries.iter().enumerate() {
            if std::ptr::eq(entry, info) {
                return Some(self.end_offsets[i]);
            }
        }
        for (i, entry) in self.entries.iter().enumerate().rev() {
            if entry == info {
                return Some(self.end_offsets[i]);
            }
        }
        Some(self.start_dir)
    }

    /// Reads and decompresses the archive member described by `info`, verifying
    /// the local file header, encryption flags, overlap bounds, and CRC-32.
    pub fn read(&self, info: &ZipInfo) -> Result<Vec<u8>, String> {
        let offset = info.header_offset as usize;
        if offset.saturating_add(SIZE_FILE_HEADER) > self.bytes.len() {
            return Err("Truncated file header".to_string());
        }
        let fheader = &self.bytes[offset..offset + SIZE_FILE_HEADER];
        if &fheader[0..4] != STRING_FILE_HEADER {
            return Err("Bad magic number for file header".to_string());
        }

        let fh_flag_bits = read_u16_le(fheader, 6);
        let fh_fname_len = read_u16_le(fheader, 26) as usize;
        let fh_extra_len = read_u16_le(fheader, 28) as usize;

        let fname_start = offset + SIZE_FILE_HEADER;
        let fname_end = fname_start
            .saturating_add(fh_fname_len)
            .min(self.bytes.len());
        let fname = &self.bytes[fname_start..fname_end];
        let data_start = fname_end.saturating_add(fh_extra_len);

        if (info.flag_bits & MASK_COMPRESSED_PATCH) != 0 {
            return Err("NotImplementedError: compressed patched data (flag bit 5)".to_string());
        }
        if (info.flag_bits & MASK_STRONG_ENCRYPTION) != 0 {
            return Err("NotImplementedError: strong encryption (flag bit 6)".to_string());
        }

        let fname_str = if (fh_flag_bits & MASK_UTF_FILENAME) != 0 {
            std::str::from_utf8(fname)
                .map_err(|e| format!("UnicodeDecodeError: {e}"))?
                .to_string()
        } else {
            decode_cp437(fname)
        };

        if fname_str != info.orig_filename {
            return Err(format!(
                "File name in directory {} and header {} differ.",
                py_str_repr(&info.orig_filename),
                py_str_repr(&fname_str)
            ));
        }

        if let Some(end_offset) = self.end_offset_for(info) {
            if (data_start as u64).saturating_add(info.compress_size) > end_offset
                && end_offset != info.header_offset
            {
                return Err(format!(
                    "Overlapped entries: {} (possible zip bomb)",
                    py_str_repr(&info.orig_filename)
                ));
            }
        }

        if (info.flag_bits & MASK_ENCRYPTED) != 0 {
            return Err(format!(
                "RuntimeError: File {} is encrypted, password required for extraction",
                py_str_repr(&info.filename)
            ));
        }

        if info.compress_type != ZIP_STORED && info.compress_type != ZIP_DEFLATED {
            return Err(
                "NotImplementedError: That compression method is not supported".to_string(),
            );
        }

        let data_end = data_start.saturating_add(info.compress_size as usize);
        if data_end > self.bytes.len() {
            return Err("Truncated file data".to_string());
        }
        let raw_data = &self.bytes[data_start..data_end];

        let mut out = if info.compress_type == ZIP_STORED {
            raw_data.to_vec()
        } else {
            inflate(raw_data)?
        };

        if (out.len() as u64) > info.file_size {
            out.truncate(info.file_size as usize);
        }

        let actual_crc = crc32(&out);
        if actual_crc != info.crc {
            return Err(format!(
                "Bad CRC-32 for file {}",
                py_str_repr(&info.filename)
            ));
        }

        Ok(out)
    }

    /// Extracts `info` into `folder`, applying `_extract_member`'s path sanitising.
    pub fn extract(&self, info: &ZipInfo, folder: &Path) -> io::Result<PathBuf> {
        let parts: Vec<&str> = info
            .filename
            .split('/')
            .filter(|&p| !p.is_empty() && p != "." && p != "..")
            .collect();

        if parts.is_empty() && !info.is_dir() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "Empty filename.",
            ));
        }

        let mut targetpath = folder.to_path_buf();
        for part in &parts {
            targetpath.push(part);
        }

        if let Some(parent) = targetpath.parent() {
            if !parent.as_os_str().is_empty() && !parent.exists() {
                fs::create_dir_all(parent)?;
            }
        }

        if info.is_dir() {
            if !targetpath.is_dir() {
                fs::create_dir_all(&targetpath)?;
            }
            return Ok(targetpath);
        }

        let data = self
            .read(info)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        fs::write(&targetpath, &data)?;
        Ok(targetpath)
    }
}

// ---------------------------------------------------------------------------
// ZipWriter
// ---------------------------------------------------------------------------

struct WrittenEntry {
    name_bytes: Vec<u8>,
    create_system: u8,
    flag_bits: u16,
    compress_type: u16,
    dostime: u16,
    dosdate: u16,
    crc: u32,
    compress_size: u32,
    file_size: u32,
    external_attr: u32,
    header_offset: u32,
}

/// Simple ZIP archive writer producing the same layout as Python's `zipfile.ZipFile`
/// with `ZipInfo(name)` (`date_time = (1980, 1, 1, 0, 0, 0)`).
pub struct ZipWriter {
    deflated: bool,
    buf: Vec<u8>,
    entries: Vec<WrittenEntry>,
}

impl ZipWriter {
    /// Creates a new `ZipWriter` using `ZIP_DEFLATED` if `deflated` is `true`,
    /// or `ZIP_STORED` if `false`.
    pub fn new(deflated: bool) -> ZipWriter {
        ZipWriter {
            deflated,
            buf: Vec::new(),
            entries: Vec::new(),
        }
    }

    /// Writes a member with `name`, `data`, `create_system`, and `external_attr`,
    /// using the constant `DEFAULT_DATE_TIME` `(1980, 1, 1, 0, 0, 0)`.
    pub fn writestr(&mut self, name: &str, data: &[u8], create_system: u8, external_attr: u32) {
        let clean_name = sanitize_filename(name);
        let (name_bytes, flag_bits) = if clean_name.is_ascii() {
            (clean_name.into_bytes(), 0u16)
        } else {
            (clean_name.into_bytes(), MASK_UTF_FILENAME)
        };

        let compress_type = if self.deflated {
            ZIP_DEFLATED
        } else {
            ZIP_STORED
        };
        let compressed = if self.deflated {
            deflate(data)
        } else {
            data.to_vec()
        };

        let crc = crc32(data);
        let compress_size = compressed.len() as u32;
        let file_size = data.len() as u32;

        let dt = DEFAULT_DATE_TIME;
        let dosdate = ((dt.0 - 1980) << 9) | ((dt.1 as u16) << 5) | (dt.2 as u16);
        let dostime = ((dt.3 as u16) << 11) | ((dt.4 as u16) << 5) | ((dt.5 as u16) / 2);

        let header_offset = self.buf.len() as u32;

        // Local file header (<4s2B4HL2L2H)
        self.buf.extend_from_slice(STRING_FILE_HEADER);
        self.buf.push(DEFAULT_VERSION);
        self.buf.push(0); // reserved
        self.buf.extend_from_slice(&flag_bits.to_le_bytes());
        self.buf.extend_from_slice(&compress_type.to_le_bytes());
        self.buf.extend_from_slice(&dostime.to_le_bytes());
        self.buf.extend_from_slice(&dosdate.to_le_bytes());
        self.buf.extend_from_slice(&crc.to_le_bytes());
        self.buf.extend_from_slice(&compress_size.to_le_bytes());
        self.buf.extend_from_slice(&file_size.to_le_bytes());
        self.buf
            .extend_from_slice(&(name_bytes.len() as u16).to_le_bytes());
        self.buf.extend_from_slice(&0u16.to_le_bytes()); // extra len
        self.buf.extend_from_slice(&name_bytes);
        self.buf.extend_from_slice(&compressed);

        self.entries.push(WrittenEntry {
            name_bytes,
            create_system,
            flag_bits,
            compress_type,
            dostime,
            dosdate,
            crc,
            compress_size,
            file_size,
            external_attr,
            header_offset,
        });
    }

    /// Writes the central directory and end-of-central-directory record and returns the archive bytes.
    pub fn finish(mut self) -> Vec<u8> {
        let start_dir = self.buf.len() as u32;
        for entry in &self.entries {
            // Central directory header (<4s4B4HL2L5H2L)
            self.buf.extend_from_slice(STRING_CENTRAL_DIR);
            self.buf.push(DEFAULT_VERSION);
            self.buf.push(entry.create_system);
            self.buf.push(DEFAULT_VERSION);
            self.buf.push(0); // reserved
            self.buf.extend_from_slice(&entry.flag_bits.to_le_bytes());
            self.buf
                .extend_from_slice(&entry.compress_type.to_le_bytes());
            self.buf.extend_from_slice(&entry.dostime.to_le_bytes());
            self.buf.extend_from_slice(&entry.dosdate.to_le_bytes());
            self.buf.extend_from_slice(&entry.crc.to_le_bytes());
            self.buf
                .extend_from_slice(&entry.compress_size.to_le_bytes());
            self.buf.extend_from_slice(&entry.file_size.to_le_bytes());
            self.buf
                .extend_from_slice(&(entry.name_bytes.len() as u16).to_le_bytes());
            self.buf.extend_from_slice(&0u16.to_le_bytes()); // extra_len
            self.buf.extend_from_slice(&0u16.to_le_bytes()); // comment_len
            self.buf.extend_from_slice(&0u16.to_le_bytes()); // disk_number_start
            self.buf.extend_from_slice(&0u16.to_le_bytes()); // internal_attr
            self.buf
                .extend_from_slice(&entry.external_attr.to_le_bytes());
            self.buf
                .extend_from_slice(&entry.header_offset.to_le_bytes());
            self.buf.extend_from_slice(&entry.name_bytes);
        }

        let pos2 = self.buf.len() as u32;
        let count = self.entries.len() as u16;
        let cd_size = pos2 - start_dir;

        // End of central directory (<4s4H2LH)
        self.buf.extend_from_slice(STRING_END_ARCHIVE);
        self.buf.extend_from_slice(&0u16.to_le_bytes()); // disk_number
        self.buf.extend_from_slice(&0u16.to_le_bytes()); // disk_start
        self.buf.extend_from_slice(&count.to_le_bytes());
        self.buf.extend_from_slice(&count.to_le_bytes());
        self.buf.extend_from_slice(&cd_size.to_le_bytes());
        self.buf.extend_from_slice(&start_dir.to_le_bytes());
        self.buf.extend_from_slice(&0u16.to_le_bytes()); // comment_len

        self.buf
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn unhex(hex: &str) -> Vec<u8> {
        let clean: Vec<u8> = hex.bytes().filter(|b| !b.is_ascii_whitespace()).collect();
        assert_eq!(clean.len() % 2, 0);
        let mut out = Vec::with_capacity(clean.len() / 2);
        for chunk in clean.chunks(2) {
            let hi = (chunk[0] as char).to_digit(16).unwrap() as u8;
            let lo = (chunk[1] as char).to_digit(16).unwrap() as u8;
            out.push((hi << 4) | lo);
        }
        out
    }

    // Fixtures built with CPython 3.12's zipfile & zlib modules:

    const PY_STORED_ZIP_HEX: &str = "\
        504b03041400000000000000210018a7557b0e0000000e00000009000000\
        68656c6c6f2e74787448656c6c6f2c20776f726c64210a504b0304140000\
        000000000021002f3adae912000000120000000a00000062696e2f72756e\
        2e736823212f62696e2f73680a6563686f2068690a504b01021403140000\
        0000000000210018a7557b0e0000000e0000000900000000000000000000\
        00a4810000000068656c6c6f2e747874504b010214031400000000000000\
        21002f3adae912000000120000000a0000000000000000000000ed813500\
        000062696e2f72756e2e7368504b050600000000020002006f0000006f00\
        00000000";

    const PY_DEFLATED_ZIP_HEX: &str = "\
        504b03041400000008000000210096c6a2651c000000e600000009000000\
        68656c6c6f2e747874f348cdc9c9d75148494dcb492c494d5128cf2fca49\
        5154f0185ec200504b010214031400000008000000210096c6a2651c0000\
        00e6000000090000000000000000000000a4810000000068656c6c6f2e74\
        7874504b0506000000000100010037000000430000000000";

    const PY_COMMENT_ZIP_HEX: &str = "\
        504b030414000000000000002100f46d5000090000000900000008000000\
        6e6f74652e7478746e6f746520626f6479504b0102140314000000000000\
        002100f46d50000900000009000000080000000d00000000000000a48100\
        0000006e6f74652e747874656e74727920636f6d6d656e74504b05060000\
        000001000100430000002f00000014006172636869766520636f6d6d656e\
        742068657265";

    const PY_ZIP64_OPEN_HEX: &str = "\
        504b03042d000000000000002100d6ec00f4ffffffffffffffff09001400\
        7a697036342e747874010010000d000000000000000d000000000000007a\
        69703634207061796c6f6164504b01022d032d000000000000002100d6ec\
        00f40d0000000d000000090000000000000000000000a481000000007a69\
        7036342e747874504b0506000000000100010037000000480000000000";

    const PY_ZIP64_BOTH_HEX: &str = "\
        504b03042d000000000000002100d6ec00f4ffffffffffffffff0c001400\
        7a697036345f63642e747874010010000d000000000000000d0000000000\
        00007a69703634207061796c6f6164504b01022d032d0000000000000021\
        00d6ec00f4ffffffffffffffff0c001c000000000000000000a481ffffff\
        ff7a697036345f63642e747874010018000d000000000000000d00000000\
        0000000000000000000000504b06062c000000000000002d002d00000000\
        00000000000100000000000000010000000000000056000000000000004b\
        00000000000000504b060700000000a10000000000000001000000504b05\
        0600000000ffffffffffffffffffffffff0000";

    const PY_CP437_ZIP_HEX: &str = "\
        504b030414000000000000002100d950ff530d0000000d0000000a000000\
        6772817373652e747874637034333720636f6e74656e74504b0102140314\
        000000000000002100d950ff530d0000000d0000000a0000000000000000\
        000000a481000000006772817373652e747874504b050600000000010001\
        0038000000350000000000";

    const PY_UTF8_DIR_SYM_ZIP_HEX: &str = "\
        504b030414000008000000002100b329855306000000060000000d000000\
        636166c3a95fe298952e747874636f66666565504b030414000000000000\
        002100000000000000000000000000070000007375626469722f504b0304\
        140000000000000021005b39253f0d0000000d000000040000006c696e6b\
        636166c3a95fe298952e747874504b0102140314000008000000002100b3\
        29855306000000060000000d0000000000000000000000a4810000000063\
        6166c3a95fe298952e747874504b01021403140000000000000021000000\
        00000000000000000000070000000000000000001000ed41310000007375\
        626469722f504b01021403140000000000000021005b39253f0d0000000d\
        000000040000000000000000000000ffa1560000006c696e6b504b050600\
        00000003000300a2000000850000000000";

    const PY_NUL_ZIP_HEX: &str = "\
        504b03041400000000000000210059d3df59080000000800000010000000\
        736166652e747874006576696c2e73686e756c2074657374504b01021403\
        1400000000000000210059d3df5908000000080000001000000000000000\
        00000000a48100000000736166652e747874006576696c2e7368504b0506\
        00000000010001003e000000360000000000";

    const PY_ENC_ZIP_HEX: &str = "\
        504b0304140001000000000021000000000004000000040000000a000000\
        7365637265742e74787431323334504b0102140314000100000000002100\
        0000000004000000040000000a0000000000000000000000a48100000000\
        7365637265742e747874504b05060000000001000100380000002c000000\
        0000";

    const PY_BAD_CRC_ZIP_HEX: &str = "\
        504b030414000000000000002100efbeadde04000000040000000b000000\
        636f72727570742e747874676f6f64504b01021403140000000000000021\
        00efbeadde04000000040000000b0000000000000000000000a481000000\
        00636f72727570742e747874504b05060000000001000100390000002d00\
        00000000";

    #[test]
    fn test_crc32_vectors() {
        assert_eq!(crc32(b""), 0x0000_0000);
        assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
        assert_eq!(crc32(b"Hello, world!\n"), 0x7B55_A718);
    }

    #[test]
    fn test_stored_zip_read_and_writer_byte_equality() {
        let expected = unhex(PY_STORED_ZIP_HEX);
        let zf = ZipFile::new(expected.clone()).expect("valid stored zip");
        assert_eq!(zf.namelist(), vec!["hello.txt", "bin/run.sh"]);
        assert_eq!(zf.infolist().len(), 2);

        let info0 = zf.getinfo("hello.txt").unwrap();
        assert!(!info0.is_dir());
        assert_eq!(info0.create_system, 3);
        assert_eq!(info0.create_version, 20);
        assert_eq!(info0.extract_version, 20);
        assert_eq!(info0.reserved, 0);
        assert_eq!(info0.flag_bits, 0);
        assert_eq!(info0.compress_type, 0);
        assert_eq!(info0.date_time, DEFAULT_DATE_TIME);
        assert_eq!(info0.external_attr, 0o100644 << 16);
        assert_eq!(zf.read(info0).unwrap(), b"Hello, world!\n");

        let info1 = zf.getinfo("bin/run.sh").unwrap();
        assert_eq!(info1.external_attr, 0o100755 << 16);
        assert_eq!(zf.read(info1).unwrap(), b"#!/bin/sh\necho hi\n");
        assert!(zf.getinfo("nonexistent").is_none());

        // Byte-for-byte equality with Python's ZIP_STORED output:
        let mut writer = ZipWriter::new(false);
        writer.writestr("hello.txt", b"Hello, world!\n", 3, 0o100644 << 16);
        writer.writestr("bin/run.sh", b"#!/bin/sh\necho hi\n", 3, 0o100755 << 16);
        let built = writer.finish();
        assert_eq!(built, expected);
    }

    #[test]
    fn test_deflated_zip_and_writer() {
        let raw = unhex(PY_DEFLATED_ZIP_HEX);
        let zf = ZipFile::new(raw).expect("valid deflated zip");
        let info = zf.getinfo("hello.txt").unwrap();
        assert_eq!(info.compress_type, 8);
        let expected_body = b"Hello, deflated world! ".repeat(10);
        assert_eq!(zf.read(info).unwrap(), expected_body);

        let mut writer = ZipWriter::new(true);
        writer.writestr("hello.txt", &expected_body, 3, 0o100644 << 16);
        writer.writestr("café.txt", "Grüß Gott\n".as_bytes(), 3, 0o100644 << 16);
        let archive_bytes = writer.finish();

        let zf2 = ZipFile::new(archive_bytes).expect("round-trip deflated zip");
        assert_eq!(zf2.namelist(), vec!["hello.txt", "café.txt"]);
        let i1 = zf2.getinfo("hello.txt").unwrap();
        assert_eq!(i1.compress_type, 8);
        assert_eq!(zf2.read(i1).unwrap(), expected_body);
        let i2 = zf2.getinfo("café.txt").unwrap();
        assert_eq!(i2.flag_bits, 0x800);
        assert_eq!(zf2.read(i2).unwrap(), "Grüß Gott\n".as_bytes());
    }

    #[test]
    fn test_zip_with_comment_and_concat() {
        let raw = unhex(PY_COMMENT_ZIP_HEX);
        let zf = ZipFile::new(raw.clone()).expect("zip with archive comment");
        let info = zf.getinfo("note.txt").unwrap();
        assert_eq!(info.comment, b"entry comment");
        assert_eq!(zf.read(info).unwrap(), b"note body");

        // Test prepended bytes (`concat` adjustment of header_offset):
        let mut prepended = b"PREPENDED_JUNK_HEADER_12345".to_vec();
        prepended.extend_from_slice(&raw);
        let zf_concat = ZipFile::new(prepended).expect("concatenated zip");
        let info_concat = zf_concat.getinfo("note.txt").unwrap();
        assert_eq!(info_concat.header_offset, 27);
        assert_eq!(zf_concat.read(info_concat).unwrap(), b"note body");
    }

    #[test]
    fn test_zip64_entries_and_eocd64() {
        let z1 = ZipFile::new(unhex(PY_ZIP64_OPEN_HEX)).expect("force_zip64=True zip");
        let info1 = z1.getinfo("zip64.txt").unwrap();
        assert_eq!(info1.file_size, 13);
        assert_eq!(info1.compress_size, 13);
        assert_eq!(z1.read(info1).unwrap(), b"zip64 payload");

        let z2 = ZipFile::new(unhex(PY_ZIP64_BOTH_HEX)).expect("full zip64 extra + eocd64");
        let info2 = z2.getinfo("zip64_cd.txt").unwrap();
        assert_eq!(info2.file_size, 13);
        assert_eq!(info2.compress_size, 13);
        assert_eq!(info2.header_offset, 0);
        assert_eq!(z2.read(info2).unwrap(), b"zip64 payload");
    }

    #[test]
    fn test_cp437_utf8_nul_dir_and_symlink() {
        let z_cp437 = ZipFile::new(unhex(PY_CP437_ZIP_HEX)).expect("cp437 zip");
        let info_cp = &z_cp437.infolist()[0];
        assert_eq!(info_cp.flag_bits & 0x800, 0);
        assert_eq!(info_cp.filename, "grüsse.txt");
        assert_eq!(z_cp437.read(info_cp).unwrap(), b"cp437 content");

        let z_multi = ZipFile::new(unhex(PY_UTF8_DIR_SYM_ZIP_HEX)).expect("utf8/dir/symlink zip");
        assert_eq!(z_multi.namelist(), vec!["café_☕.txt", "subdir/", "link"]);

        let info_utf8 = z_multi.getinfo("café_☕.txt").unwrap();
        assert_eq!(info_utf8.flag_bits & 0x800, 0x800);
        assert!(!info_utf8.is_dir());
        assert_eq!(z_multi.read(info_utf8).unwrap(), b"coffee");

        let info_dir = z_multi.getinfo("subdir/").unwrap();
        assert!(info_dir.is_dir());
        assert_eq!(z_multi.read(info_dir).unwrap(), b"");

        let info_sym = z_multi.getinfo("link").unwrap();
        assert!(!info_sym.is_dir());
        assert_eq!(info_sym.create_system, 3);
        assert_eq!(info_sym.external_attr, 0o120777 << 16);
        assert_eq!(z_multi.read(info_sym).unwrap(), "café_☕.txt".as_bytes());

        let z_nul = ZipFile::new(unhex(PY_NUL_ZIP_HEX)).expect("nul filename zip");
        let info_nul = &z_nul.infolist()[0];
        assert_eq!(info_nul.filename, "safe.txt");
        assert_eq!(info_nul.orig_filename, "safe.txt\0evil.sh");
        assert_eq!(z_nul.read(info_nul).unwrap(), b"nul test");
    }

    #[test]
    fn test_error_conditions_and_safety_checks() {
        // 1. Truncated / non-zip files
        assert_eq!(
            ZipFile::new(b"not a zip".to_vec()).err().unwrap(),
            "File is not a zip file"
        );
        let stored = unhex(PY_STORED_ZIP_HEX);
        assert_eq!(
            ZipFile::new(stored[..15].to_vec()).err().unwrap(),
            "File is not a zip file"
        );

        // 2. Encrypted entry
        let z_enc = ZipFile::new(unhex(PY_ENC_ZIP_HEX)).unwrap();
        let err_enc = z_enc.read(&z_enc.infolist()[0]).unwrap_err();
        assert_eq!(
            err_enc,
            "RuntimeError: File 'secret.txt' is encrypted, password required for extraction"
        );

        // 3. Bad CRC-32
        let z_bad_crc = ZipFile::new(unhex(PY_BAD_CRC_ZIP_HEX)).unwrap();
        let err_crc = z_bad_crc.read(&z_bad_crc.infolist()[0]).unwrap_err();
        assert_eq!(err_crc, "Bad CRC-32 for file 'corrupt.txt'");

        // 4. Invalid UTF-8 under flag 0x800
        let mut bad_utf8_zip = unhex(PY_CP437_ZIP_HEX);
        // Set flag_bits = 0x0800 in central directory (offset 43 + 8 = 51):
        let cd_off = 30 + 10 + 13;
        bad_utf8_zip[cd_off + 8] = 0x00;
        bad_utf8_zip[cd_off + 9] = 0x08;
        let err_utf8 = ZipFile::new(bad_utf8_zip).err().unwrap();
        assert!(
            err_utf8.starts_with("UnicodeDecodeError:"),
            "got: {err_utf8}"
        );

        // 5. Local header filename mismatch
        let mut diff_name_zip = unhex(PY_CP437_ZIP_HEX);
        diff_name_zip[30] = b'X'; // change local header filename first byte
        let z_diff = ZipFile::new(diff_name_zip).unwrap();
        let err_diff = z_diff.read(&z_diff.infolist()[0]).unwrap_err();
        assert_eq!(
            err_diff,
            "File name in directory 'grüsse.txt' and header 'Xrüsse.txt' differ."
        );

        // 6. Bad local file header magic
        let mut bad_fh_zip = unhex(PY_CP437_ZIP_HEX);
        bad_fh_zip[0] = b'X';
        let z_bad_fh = ZipFile::new(bad_fh_zip).unwrap();
        assert_eq!(
            z_bad_fh.read(&z_bad_fh.infolist()[0]).unwrap_err(),
            "Bad magic number for file header"
        );

        // 7. Bad central directory magic
        let mut bad_cd_zip = unhex(PY_CP437_ZIP_HEX);
        bad_cd_zip[cd_off] = b'X';
        assert_eq!(
            ZipFile::new(bad_cd_zip).err().unwrap(),
            "Bad magic number for central directory"
        );

        // 8. Truncated central directory
        let mut trunc_cd_zip = unhex(PY_CP437_ZIP_HEX);
        let eocd_off = trunc_cd_zip.len() - 22;
        // Set size_cd to 10 (less than 46) and adjust offset_cd so concat == 0
        let new_offset_cd = (eocd_off - 10) as u32;
        trunc_cd_zip[eocd_off + 12..eocd_off + 16].copy_from_slice(&10u32.to_le_bytes());
        trunc_cd_zip[eocd_off + 16..eocd_off + 20].copy_from_slice(&new_offset_cd.to_le_bytes());
        assert_eq!(
            ZipFile::new(trunc_cd_zip).err().unwrap(),
            "Truncated central directory"
        );

        // 9. Corrupt extra field in central directory
        let mut bad_extra_zip = unhex(PY_ZIP64_BOTH_HEX);
        // In PY_ZIP64_BOTH_HEX, CD starts at 0x4b (75), extra starts at 75 + 46 + 12 = 133
        // Change extra field size from 24 to 99:
        bad_extra_zip[133 + 2] = 99;
        assert_eq!(
            ZipFile::new(bad_extra_zip).err().unwrap(),
            "Corrupt extra field 0001 (size=99)"
        );

        // 10. Unsupported compression method
        let mut bzip2_zip = unhex(PY_CP437_ZIP_HEX);
        bzip2_zip[cd_off + 10] = 12; // BZIP2
        let z_bz2 = ZipFile::new(bzip2_zip).unwrap();
        assert_eq!(
            z_bz2.read(&z_bz2.infolist()[0]).unwrap_err(),
            "NotImplementedError: That compression method is not supported"
        );

        // 11. Overlapped entries check
        let mut overlap_zip = unhex(PY_STORED_ZIP_HEX);
        // Stored zip has 2 entries; increase first entry's compress_size in CD (at offset 111 + 20 = 131) to 100
        overlap_zip[111 + 20..111 + 24].copy_from_slice(&100u32.to_le_bytes());
        let z_overlap = ZipFile::new(overlap_zip).unwrap();
        assert_eq!(
            z_overlap.read(&z_overlap.infolist()[0]).unwrap_err(),
            "Overlapped entries: 'hello.txt' (possible zip bomb)"
        );
    }

    #[test]
    fn test_extract_and_path_sanitising() {
        let mut writer = ZipWriter::new(true);
        writer.writestr("dir/sub/", b"", 3, (0o40755 << 16) | 0x10);
        writer.writestr("dir/sub/file.txt", b"inside sub", 3, 0o100644 << 16);
        writer.writestr("/.././escaped//clean.txt", b"sanitised", 3, 0o100644 << 16);
        let zf = ZipFile::new(writer.finish()).unwrap();

        let tmp = std::env::temp_dir().join(format!("zip_rs_test_{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();

        for info in zf.infolist() {
            let written = zf.extract(info, &tmp).unwrap();
            assert!(written.starts_with(&tmp));
        }

        assert!(tmp.join("dir/sub").is_dir());
        assert_eq!(
            fs::read(tmp.join("dir/sub/file.txt")).unwrap(),
            b"inside sub"
        );
        assert_eq!(
            fs::read(tmp.join("escaped/clean.txt")).unwrap(),
            b"sanitised"
        );

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_inflate_zlib_levels_0_1_6_9() {
        // 1. Short sample (L0 = stored block btype 0, L1/L6/L9 = fixed Huffman block btype 1)
        let short_expected = b"Hello, world! Hello, world! Hello, world!";
        let short_l0 = unhex("012900d6ff48656c6c6f2c20776f726c64212048656c6c6f2c20776f726c64212048656c6c6f2c20776f726c6421");
        let short_l1_6_9 = unhex("f348cdc9c9d75128cf2fca495154f0c0cd0300");
        assert_eq!(inflate(&short_l0).unwrap(), short_expected);
        assert_eq!(inflate(&short_l1_6_9).unwrap(), short_expected);

        // 2. Fixed Huffman block where L1, L6, and L9 differ
        let mut mid_expected = Vec::new();
        let base: Vec<u8> = (65..125).collect();
        mid_expected.push(b'Z');
        mid_expected.extend_from_slice(&base[..60]);
        mid_expected.push(b'W');
        for _ in 0..10 {
            mid_expected.extend_from_slice(b"0123456789abcdef");
        }
        mid_expected.push(b'X');
        mid_expected.extend_from_slice(&base[..35]);
        mid_expected.push(b'Y');
        mid_expected.push(b'X');
        mid_expected.extend_from_slice(&base[..60]);
        mid_expected.push(b'W');

        let mid_l1_6 = unhex(
            "\
            8b72747276717573f7f0f4f2f6f1f5f30f080c0a0e090d0b8f888c8a8e898d8b\
            4f484c4a4e494d4bcfc8cccacec9cdcb2f282c2a2e292d2bafa8acaaae093730\
            343236313533b7b084281b6cfc08227c17498c22dc410000",
        );
        let mid_l9 = unhex(
            "\
            8b72747276717573f7f0f4f2f6f1f5f30f080c0a0e090d0b8f888c8a8e898d8b\
            4f484c4a4e494d4bcfc8cccacec9cdcb2f282c2a2e292d2bafa8acaaae093730\
            343236313533b7b084281b6cfc08227c17194151100000",
        );
        assert_eq!(inflate(&mid_l1_6).unwrap(), mid_expected);
        assert_eq!(inflate(&mid_l9).unwrap(), mid_expected);

        // 3. Dynamic Huffman blocks (btype = 2) from zlib at L0, L1, L6, L9
        let alphabet = b"AAAAAAAABBBBCCDE";
        let mut state = 1u32;
        let mut dyn_expected = Vec::with_capacity(300);
        for _ in 0..300 {
            state = state.wrapping_mul(1_103_515_245).wrapping_add(12345) & 0x7fff_ffff;
            dyn_expected.push(alphabet[(state >> 27) as usize]);
        }
        let dyn_l0 = unhex(
            "\
            012c01d3fe424141424541424141414141414145424342434343414241414442\
            4142434443434243424141414341414541414542414343454141434142414541\
            4141444241424141414141434141414141424241414341414141414441424142\
            4245414345434142434141414343414141434142424145414143434445414141\
            4141454242414143414141414542454143424141424142414143424142414542\
            4242424341414142414241414142414241414141454141424142414241414241\
            4241434343444242414242414143414141434141414141424241424142424242\
            4143424142424344444143444241414141434241414141424242414341414142\
            4142444142414542414143434241424141414141414143414342414141424142\
            4541414141414144454245424141414141",
        );
        let dyn_l1 = unhex(
            "\
            3d8f8b1180300843672381fd57f20554ce6b857c1a54a529d5d5c8b29dbe5572\
            9b3ea0ab864f657387c0b59c15025382797f0d41f87aa06684e7ca566777d4f1\
            fb1413320d327839c1b4d21d1db021d2bf4ca236169fcb9f222386f161872e58\
            796e3709b4290113939d48471306e5a331b88cd5643bf001",
        );
        let dyn_l6_9 = unhex(
            "\
            3d50b101c03008ba4dd0ff5f2aa04d071b048504559842ed3720481a370a6c0a\
            9ba438d3458e110ca3c91c5381ffd4ea437b3992bac5142b3cce9eb3fb27c662\
            812ca4ab3864743dce69f6744a456de0f9be146ee9e73dba4397544989e551b7\
            b7e3e340784fc095c1cfb27751b6253f",
        );

        assert_eq!(inflate(&dyn_l0).unwrap(), dyn_expected);
        assert_eq!(inflate(&dyn_l1).unwrap(), dyn_expected);
        assert_eq!(inflate(&dyn_l6_9).unwrap(), dyn_expected);
    }

    #[test]
    fn test_deflate_roundtrip_and_compression_ratio() {
        // 1. Empty
        let empty_comp = deflate(b"");
        assert_eq!(inflate(&empty_comp).unwrap(), b"");

        // 2. 1 byte
        let one_comp = deflate(b"Z");
        assert_eq!(inflate(&one_comp).unwrap(), b"Z");

        // 3. 100 KB of repetitive text (must compress to < 5 KB)
        let sentence = b"The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs.\n";
        let mut text_100k = Vec::with_capacity(102_400);
        while text_100k.len() < 102_400 {
            text_100k.extend_from_slice(sentence);
        }
        text_100k.truncate(102_400);
        let comp_100k = deflate(&text_100k);
        assert!(
            comp_100k.len() < 5_000,
            "expected < 5000 bytes, got {}",
            comp_100k.len()
        );
        assert_eq!(inflate(&comp_100k).unwrap(), text_100k);

        // 4. 100 KB of varied prose-like text (sliding window + dynamic Huffman)
        let mut varied_100k = Vec::with_capacity(102_400);
        let words = [
            "catalog",
            "version",
            "manifest",
            "signature",
            "ed25519",
            "archive",
            "central",
            "directory",
            "deflate",
            "inflate",
            "huffman",
            "window",
            "vitruvian",
            "protocol",
            "minimum",
            "checksum",
            "download",
            "release",
            "universal",
            "macho",
        ];
        let mut s = 0x1234_5678u32;
        while varied_100k.len() < 102_400 {
            s = s ^ (s << 13);
            s = s ^ (s >> 17);
            s = s ^ (s << 5);
            let w = words[(s as usize) % words.len()];
            varied_100k.extend_from_slice(w.as_bytes());
            varied_100k.push(if (s & 0xF) == 0 { b'\n' } else { b' ' });
        }
        varied_100k.truncate(102_400);
        let comp_varied = deflate(&varied_100k);
        assert!(comp_varied.len() < varied_100k.len() / 2);
        assert_eq!(inflate(&comp_varied).unwrap(), varied_100k);

        // 5. 300 KB of pseudo-random bytes
        let mut prng_300k = Vec::with_capacity(307_200);
        let mut x = 0xDEAD_BEEFu64;
        for _ in 0..307_200 {
            x = x.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1);
            prng_300k.push((x >> 56) as u8);
        }
        let comp_300k = deflate(&prng_300k);
        assert_eq!(inflate(&comp_300k).unwrap(), prng_300k);

        // 6. Highly repetitive data (single byte run > 64 KB)
        let rep = vec![b'A'; 150_000];
        let comp_rep = deflate(&rep);
        assert!(comp_rep.len() < 500);
        assert_eq!(inflate(&comp_rep).unwrap(), rep);

        // Cross-check with Python 3.12's zlib.decompress(x, -15) if available:
        let py_bin = "/Users/james/.cache/bazel/worktrees/vitruvian-core-feat-catalog-tools-rust/a4390578bde5d4782d9428efd44a312d/external/rules_python++python+python_3_12_aarch64-apple-darwin/bin/python3";
        if Path::new(py_bin).exists() {
            let tmp = std::env::temp_dir().join(format!("zip_zlib_check_{}", std::process::id()));
            let _ = fs::create_dir_all(&tmp);
            for (idx, (orig, comp)) in [
                (&b""[..], &empty_comp),
                (&b"Z"[..], &one_comp),
                (&text_100k[..], &comp_100k),
                (&varied_100k[..], &comp_varied),
                (&prng_300k[..], &comp_300k),
                (&rep[..], &comp_rep),
            ]
            .iter()
            .enumerate()
            {
                let comp_path = tmp.join(format!("c_{idx}.bin"));
                let out_path = tmp.join(format!("o_{idx}.bin"));
                fs::write(&comp_path, comp).unwrap();
                let status = std::process::Command::new(py_bin)
                    .arg("-c")
                    .arg("import sys, zlib; open(sys.argv[2], 'wb').write(zlib.decompress(open(sys.argv[1], 'rb').read(), -15))")
                    .arg(&comp_path)
                    .arg(&out_path)
                    .status()
                    .unwrap();
                assert!(status.success(), "zlib.decompress failed for case {idx}");
                let decomp = fs::read(&out_path).unwrap();
                assert_eq!(&decomp[..], *orig, "zlib roundtrip mismatch for case {idx}");
            }
            let _ = fs::remove_dir_all(&tmp);
        }
    }
}
