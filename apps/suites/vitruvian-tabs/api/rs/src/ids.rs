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

use crate::crypto::{hex_encode, now_epoch_ms, random_bytes};
use crate::sha256;

fn to_base36(mut n: u64) -> String {
    const DIGITS: &[u8; 36] = b"0123456789abcdefghijklmnopqrstuvwxyz";
    if n == 0 {
        return "0".to_string();
    }
    let mut chars = Vec::new();
    while n > 0 {
        chars.push(DIGITS[(n % 36) as usize] as char);
        n /= 36;
    }
    chars.into_iter().rev().collect()
}

/// Generate a prefixed identifier matching `<prefix>_<base36 timestamp>_<9-char base36 random>`.
pub fn generate_id(prefix: &str) -> String {
    let ts = to_base36(now_epoch_ms().max(0) as u64);
    let rand = random_bytes(8);
    let mut rand_u64 = u64::from_be_bytes([
        rand[0], rand[1], rand[2], rand[3], rand[4], rand[5], rand[6], rand[7],
    ]);
    let mut suffix = String::with_capacity(9);
    const DIGITS: &[u8; 36] = b"0123456789abcdefghijklmnopqrstuvwxyz";
    for _ in 0..9 {
        suffix.push(DIGITS[(rand_u64 % 36) as usize] as char);
        rand_u64 /= 36;
        if rand_u64 == 0 {
            rand_u64 = 0x9e37_79b9_7f4a_7c15;
        }
    }
    format!("{prefix}_{ts}_{suffix}")
}

/// Generate a 256-bit (32-byte) opaque token encoded as 64 lowercase hex characters.
pub fn generate_opaque_token() -> String {
    hex_encode(&random_bytes(32))
}

/// SHA-256 hex digest of an opaque token (`hashToken` in `src/lib/ids.ts`).
pub fn hash_token(token: &str) -> String {
    hex_encode(&sha256(token.as_bytes()))
}
