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

//! Deterministic packet recording and replay format (`<t_us> <40 hex chars>`).

use crate::bindings::Action;
use crate::engine::Engine;
use std::fmt;

/// A single timestamped 20-byte BLE packet from a replay log.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ReplayRecord {
    /// Timestamp in microseconds.
    pub t_us: u64,
    /// Raw 20-byte BLE notification payload.
    pub packet: [u8; 20],
}

/// Error returned when parsing a replay file fails.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReplayError {
    /// 1-based line number where the error occurred (0 if line-independent).
    pub line: usize,
    /// Human-readable description of the parse error.
    pub message: String,
}

impl fmt::Display for ReplayError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.line > 0 {
            write!(f, "line {}: {}", self.line, self.message)
        } else {
            write!(f, "{}", self.message)
        }
    }
}

impl std::error::Error for ReplayError {}

/// Parses a single `<t_us> <40 hex chars>` line.
///
/// Blank lines and lines starting with `#` (after trimming leading whitespace) return `Ok(None)`.
pub fn parse_line(line: &str) -> Result<Option<ReplayRecord>, ReplayError> {
    let trimmed = line.trim();
    if trimmed.is_empty() || trimmed.starts_with('#') {
        return Ok(None);
    }

    let mut parts = trimmed.split_whitespace();
    let t_str = parts.next().ok_or_else(|| ReplayError {
        line: 0,
        message: "missing timestamp".to_string(),
    })?;
    let hex_str = parts.next().ok_or_else(|| ReplayError {
        line: 0,
        message: "missing 40-char hex packet".to_string(),
    })?;
    if parts.next().is_some() {
        return Err(ReplayError {
            line: 0,
            message: "unexpected trailing tokens on replay line".to_string(),
        });
    }

    let t_us = t_str.parse::<u64>().map_err(|e| ReplayError {
        line: 0,
        message: format!("invalid timestamp '{}': {}", t_str, e),
    })?;

    if hex_str.len() != 40 {
        return Err(ReplayError {
            line: 0,
            message: format!("expected 40 hex chars, got {}", hex_str.len()),
        });
    }

    let mut packet = [0u8; 20];
    for (i, chunk) in hex_str.as_bytes().chunks_exact(2).enumerate() {
        let hi = decode_nibble(chunk[0]).ok_or_else(|| ReplayError {
            line: 0,
            message: format!("invalid hex character '{}'", chunk[0] as char),
        })?;
        let lo = decode_nibble(chunk[1]).ok_or_else(|| ReplayError {
            line: 0,
            message: format!("invalid hex character '{}'", chunk[1] as char),
        })?;
        packet[i] = (hi << 4) | lo;
    }

    Ok(Some(ReplayRecord { t_us, packet }))
}

/// Parses a multi-line replay transcript into a vector of [`ReplayRecord`]s.
pub fn parse(input: &str) -> Result<Vec<ReplayRecord>, ReplayError> {
    let mut records = Vec::new();
    for (idx, line) in input.lines().enumerate() {
        match parse_line(line) {
            Ok(Some(rec)) => records.push(rec),
            Ok(None) => {}
            Err(mut err) => {
                err.line = idx + 1;
                return Err(err);
            }
        }
    }
    Ok(records)
}

/// Formats a single `(t_us, packet)` pair as `<t_us> <40 lowercase hex chars>`.
pub fn format_line(t_us: u64, packet: &[u8; 20]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(64);
    out.push_str(&t_us.to_string());
    out.push(' ');
    for &b in packet {
        out.push(HEX[(b >> 4) as usize] as char);
        out.push(HEX[(b & 0x0F) as usize] as char);
    }
    out
}

/// Serializes a slice of [`ReplayRecord`]s into the newline-delimited replay format.
pub fn write(records: &[ReplayRecord]) -> String {
    let mut out = String::new();
    for rec in records {
        out.push_str(&format_line(rec.t_us, &rec.packet));
        out.push('\n');
    }
    out
}

/// Parses `input` and feeds every record sequentially into `engine`, returning all emitted [`Action`]s.
pub fn replay_into(engine: &mut Engine, input: &str) -> Result<Vec<Action>, ReplayError> {
    let records = parse(input)?;
    let mut actions = Vec::new();
    for rec in records {
        actions.extend(engine.feed(&rec.packet, rec.t_us));
    }
    Ok(actions)
}

#[inline]
fn decode_nibble(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}
