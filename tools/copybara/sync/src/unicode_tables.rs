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

// Shared with the other ported tools, so not repeated here.
// Go 1.26.6 strconv.IsPrint (Unicode 15.0.0) matches Python 3.12's
// str.isprintable() (PRINTABLE) on every code point 0..=0x10FFFF.
pub use vitruvian_pycompat::unicode_tables::PRINTABLE as PRINT;

#[cfg(test)]
mod tests {
    use super::PRINT;

    /// Expected per-plane (code-point count, SHA-256 of 8192-byte LSB-first bitset)
    /// and overall totals across 0..=0x10FFFF generated from the original Go 1.26.6
    /// PRINT table in tools/copybara/sync/src/unicode_tables.rs before switching to
    /// vitruvian_pycompat::unicode_tables::PRINTABLE.
    const EXPECTED_PLANES: [(usize, &str); 17] = [
        (
            55508,
            "3f2026488880e1608ac19068c224ecb67eb33e2df9280948b3ddfcf3a6c0aaf8",
        ),
        (
            23246,
            "c6fadc1a19e1a3334ec324df2075ea7848cad2323196676406ec5c09fbed4d90",
        ),
        (
            60873,
            "8fe260201bf38f56b233a855c02f3a9d3a712cb685bebf866300f5310f25c7ab",
        ),
        (
            9131,
            "ec6c9d33e6af638d5dc786a2c1cbbdac34397a76d5cd6d865484727968e2f568",
        ),
        (
            0,
            "9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47",
        ),
        (
            0,
            "9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47",
        ),
        (
            0,
            "9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47",
        ),
        (
            0,
            "9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47",
        ),
        (
            0,
            "9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47",
        ),
        (
            0,
            "9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47",
        ),
        (
            0,
            "9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47",
        ),
        (
            0,
            "9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47",
        ),
        (
            0,
            "9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47",
        ),
        (
            0,
            "9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47",
        ),
        (
            240,
            "e2447e2711b5217535ca020b62aaaec7b4e6ff6209a638481d1429ab3dd6326e",
        ),
        (
            0,
            "9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47",
        ),
        (
            0,
            "9f1dcbc35c350d6027f98be0f5c8b43b42ca52b7604459c0c42be3aa88913d47",
        ),
    ];
    const EXPECTED_TOTAL_COUNT: usize = 148998;
    const EXPECTED_TOTAL_SHA256: &str =
        "dbe4beecc0027b38c16c32d304958e611e27baa40412efea4cf616346eb631a2";

    fn in_table(table: &[(u32, u32)], cp: u32) -> bool {
        table
            .binary_search_by(|&(lo, hi)| {
                if hi < cp {
                    std::cmp::Ordering::Less
                } else if lo > cp {
                    std::cmp::Ordering::Greater
                } else {
                    std::cmp::Ordering::Equal
                }
            })
            .is_ok()
    }

    struct Sha256 {
        state: [u32; 8],
        buf: [u8; 64],
        buf_len: usize,
        total_len: u64,
    }

    impl Sha256 {
        const H0: [u32; 8] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
            0x5be0cd19,
        ];
        const K: [u32; 64] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
            0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
            0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
            0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
            0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
            0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
            0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
            0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
            0xc67178f2,
        ];

        fn new() -> Self {
            Self {
                state: Self::H0,
                buf: [0; 64],
                buf_len: 0,
                total_len: 0,
            }
        }

        fn compress(state: &mut [u32; 8], block: &[u8; 64]) {
            let mut w = [0u32; 64];
            for (i, word) in w.iter_mut().take(16).enumerate() {
                let b = i * 4;
                *word = u32::from_be_bytes([block[b], block[b + 1], block[b + 2], block[b + 3]]);
            }
            for i in 16..64 {
                let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
                let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
                w[i] = w[i - 16]
                    .wrapping_add(s0)
                    .wrapping_add(w[i - 7])
                    .wrapping_add(s1);
            }
            let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut h] = *state;
            for i in 0..64 {
                let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
                let ch = (e & f) ^ ((!e) & g);
                let temp1 = h
                    .wrapping_add(s1)
                    .wrapping_add(ch)
                    .wrapping_add(Self::K[i])
                    .wrapping_add(w[i]);
                let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
                let maj = (a & b) ^ (a & c) ^ (b & c);
                let temp2 = s0.wrapping_add(maj);
                h = g;
                g = f;
                f = e;
                e = d.wrapping_add(temp1);
                d = c;
                c = b;
                b = a;
                a = temp1.wrapping_add(temp2);
            }
            for (dst, add) in state.iter_mut().zip([a, b, c, d, e, f, g, h]) {
                *dst = dst.wrapping_add(add);
            }
        }

        fn update(&mut self, mut data: &[u8]) {
            self.total_len += data.len() as u64;
            if self.buf_len > 0 {
                let take = (64 - self.buf_len).min(data.len());
                self.buf[self.buf_len..self.buf_len + take].copy_from_slice(&data[..take]);
                self.buf_len += take;
                data = &data[take..];
                if self.buf_len == 64 {
                    let block = self.buf;
                    Self::compress(&mut self.state, &block);
                    self.buf_len = 0;
                }
            }
            while data.len() >= 64 {
                let block: &[u8; 64] = data[..64].try_into().unwrap();
                Self::compress(&mut self.state, block);
                data = &data[64..];
            }
            if !data.is_empty() {
                self.buf[..data.len()].copy_from_slice(data);
                self.buf_len = data.len();
            }
        }

        fn finalize(mut self) -> [u8; 32] {
            let bit_len = self.total_len * 8;
            self.buf[self.buf_len] = 0x80;
            self.buf_len += 1;
            if self.buf_len > 56 {
                self.buf[self.buf_len..].fill(0);
                let block = self.buf;
                Self::compress(&mut self.state, &block);
                self.buf_len = 0;
            }
            self.buf[self.buf_len..56].fill(0);
            self.buf[56..64].copy_from_slice(&bit_len.to_be_bytes());
            let block = self.buf;
            Self::compress(&mut self.state, &block);
            let mut out = [0u8; 32];
            for (i, word) in self.state.iter().enumerate() {
                out[i * 4..i * 4 + 4].copy_from_slice(&word.to_be_bytes());
            }
            out
        }

        fn digest(data: &[u8]) -> [u8; 32] {
            let mut h = Self::new();
            h.update(data);
            h.finalize()
        }
    }

    fn to_hex(bytes: &[u8; 32]) -> String {
        let mut s = String::with_capacity(64);
        for &b in bytes {
            s.push(char::from_digit((b >> 4) as u32, 16).unwrap());
            s.push(char::from_digit((b & 15) as u32, 16).unwrap());
        }
        s
    }

    #[test]
    fn shared_print_matches_old_table_for_every_code_point() {
        let mut total_hasher = Sha256::new();
        let mut total_count = 0usize;
        for plane in 0u32..=16 {
            let mut buf = [0u8; 8192];
            let mut plane_count = 0usize;
            for offset in 0u32..65536 {
                let cp = (plane << 16) | offset;
                let in_print = in_table(PRINT, cp);
                if let Some(c) = char::from_u32(cp) {
                    assert_eq!(
                        crate::gostr::is_print(c),
                        in_print,
                        "gostr::is_print mismatch at {cp:#x}"
                    );
                }
                if in_print {
                    buf[(offset >> 3) as usize] |= 1 << (offset & 7);
                    plane_count += 1;
                }
            }
            total_count += plane_count;
            total_hasher.update(&buf);
            let plane_hex = to_hex(&Sha256::digest(&buf));
            let (exp_count, exp_hex) = EXPECTED_PLANES[plane as usize];
            assert_eq!(
                (plane_count, plane_hex.as_str()),
                (exp_count, exp_hex),
                "plane {plane} mismatch against original tools/copybara/sync PRINT table"
            );
        }
        let total_hex = to_hex(&total_hasher.finalize());
        assert_eq!(
            (total_count, total_hex.as_str()),
            (EXPECTED_TOTAL_COUNT, EXPECTED_TOTAL_SHA256),
            "total 0..=0x10FFFF mismatch against original tools/copybara/sync PRINT table"
        );
    }
}
