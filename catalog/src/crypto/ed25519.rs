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

//! Ed25519 (RFC 8032): a public key from a private one, signing, and
//! verifying the way OpenSSL does (S must be below L, and the R the
//! signature carries must be byte for byte the R the check computes).
//!
//! Field elements are five 51-bit limbs mod p = 2^255 - 19; points are in
//! extended coordinates on -x^2 + y^2 = 1 + d x^2 y^2, added with the
//! complete formula; scalars are reduced mod L bit by bit. Speed is not the
//! point: the catalog signs one file.

use super::sha512;

const MASK: u64 = (1 << 51) - 1;

#[derive(Clone, Copy, Debug)]
struct Fe([u64; 5]);

fn load8(b: &[u8], at: usize) -> u64 {
    let mut w = [0u8; 8];
    let end = (at + 8).min(b.len());
    w[..end - at].copy_from_slice(&b[at..end]);
    u64::from_le_bytes(w)
}

impl Fe {
    const ZERO: Fe = Fe([0; 5]);
    const ONE: Fe = Fe([1, 0, 0, 0, 0]);

    fn small(n: u64) -> Fe {
        Fe([n, 0, 0, 0, 0])
    }

    /// The low 255 bits of 32 little-endian bytes.
    fn from_bytes(b: &[u8; 32]) -> Fe {
        Fe([
            load8(b, 0) & MASK,
            (load8(b, 6) >> 3) & MASK,
            (load8(b, 12) >> 6) & MASK,
            (load8(b, 19) >> 1) & MASK,
            (load8(b, 24) >> 12) & MASK,
        ])
    }

    fn carry(mut l: [u64; 5]) -> Fe {
        for _ in 0..2 {
            for i in 0..4 {
                l[i + 1] += l[i] >> 51;
                l[i] &= MASK;
            }
            l[0] += 19 * (l[4] >> 51);
            l[4] &= MASK;
        }
        Fe(l)
    }

    /// The canonical 32 bytes: fully reduced below p.
    fn to_bytes(self) -> [u8; 32] {
        let mut l = Fe::carry(self.0).0;
        // q is 1 when the value is p or more.
        let mut q = (l[0] + 19) >> 51;
        for limb in l.iter().skip(1) {
            q = (limb + q) >> 51;
        }
        l[0] += 19 * q;
        for i in 0..4 {
            l[i + 1] += l[i] >> 51;
            l[i] &= MASK;
        }
        l[4] &= MASK;
        let mut acc: u128 = 0;
        let mut bits = 0;
        let mut out = [0u8; 32];
        let mut k = 0;
        for limb in l {
            acc |= (limb as u128) << bits;
            bits += 51;
            while bits >= 8 && k < 32 {
                out[k] = acc as u8;
                acc >>= 8;
                bits -= 8;
                k += 1;
            }
        }
        if k < 32 {
            out[k] = acc as u8;
        }
        out
    }

    fn add(self, o: Fe) -> Fe {
        let mut l = [0u64; 5];
        for (i, x) in l.iter_mut().enumerate() {
            *x = self.0[i] + o.0[i];
        }
        Fe::carry(l)
    }

    fn sub(self, o: Fe) -> Fe {
        // + 4p keeps every limb positive.
        let four_p = [
            (1u64 << 53) - 76,
            (1 << 53) - 4,
            (1 << 53) - 4,
            (1 << 53) - 4,
            (1 << 53) - 4,
        ];
        let o = Fe::carry(o.0);
        let mut l = [0u64; 5];
        for (i, x) in l.iter_mut().enumerate() {
            *x = self.0[i] + four_p[i] - o.0[i];
        }
        Fe::carry(l)
    }

    fn neg(self) -> Fe {
        Fe::ZERO.sub(self)
    }

    fn mul(self, o: Fe) -> Fe {
        let a = self.0.map(|x| x as u128);
        let b = o.0.map(|x| x as u128);
        let b19 = [b[0], b[1] * 19, b[2] * 19, b[3] * 19, b[4] * 19];
        let r0 = a[0] * b[0] + a[1] * b19[4] + a[2] * b19[3] + a[3] * b19[2] + a[4] * b19[1];
        let r1 = a[0] * b[1] + a[1] * b[0] + a[2] * b19[4] + a[3] * b19[3] + a[4] * b19[2];
        let r2 = a[0] * b[2] + a[1] * b[1] + a[2] * b[0] + a[3] * b19[4] + a[4] * b19[3];
        let r3 = a[0] * b[3] + a[1] * b[2] + a[2] * b[1] + a[3] * b[0] + a[4] * b19[4];
        let r4 = a[0] * b[4] + a[1] * b[3] + a[2] * b[2] + a[3] * b[1] + a[4] * b[0];
        let mut r = [r0, r1, r2, r3, r4];
        for i in 0..4 {
            r[i + 1] += r[i] >> 51;
            r[i] &= MASK as u128;
        }
        let top = r[4] >> 51;
        r[4] &= MASK as u128;
        r[0] += top * 19;
        Fe::carry(r.map(|x| x as u64))
    }

    fn square(self) -> Fe {
        self.mul(self)
    }

    /// self^e, e as 32 little-endian bytes.
    fn pow(self, e: &[u8; 32]) -> Fe {
        let mut r = Fe::ONE;
        for i in (0..256).rev() {
            r = r.square();
            if (e[i / 8] >> (i % 8)) & 1 == 1 {
                r = r.mul(self);
            }
        }
        r
    }

    fn invert(self) -> Fe {
        let mut e = [0xffu8; 32];
        e[0] = 0xeb;
        e[31] = 0x7f;
        self.pow(&e)
    }

    fn is_negative(self) -> bool {
        self.to_bytes()[0] & 1 == 1
    }

    fn is_zero(self) -> bool {
        self.to_bytes() == [0u8; 32]
    }

    /// `a` when `pick` is false, `b` when it is true, without branching on it.
    fn select(a: Fe, b: Fe, pick: bool) -> Fe {
        let mask = (pick as u64).wrapping_neg();
        let mut l = [0u64; 5];
        for (i, x) in l.iter_mut().enumerate() {
            *x = a.0[i] ^ (mask & (a.0[i] ^ b.0[i]));
        }
        Fe(l)
    }
}

fn d() -> Fe {
    Fe::small(121665).neg().mul(Fe::small(121666).invert())
}

fn sqrt_m1() -> Fe {
    // 2^((p-1)/4)
    let mut e = [0xffu8; 32];
    e[0] = 0xfb;
    e[31] = 0x1f;
    Fe::small(2).pow(&e)
}

#[derive(Clone, Copy, Debug)]
struct Point {
    x: Fe,
    y: Fe,
    z: Fe,
    t: Fe,
}

impl Point {
    fn identity() -> Point {
        Point {
            x: Fe::ZERO,
            y: Fe::ONE,
            z: Fe::ONE,
            t: Fe::ZERO,
        }
    }

    /// The complete addition formula for a = -1 (add-2008-hwcd-3).
    fn add(self, o: Point, d2: Fe) -> Point {
        let a = self.y.sub(self.x).mul(o.y.sub(o.x));
        let b = self.y.add(self.x).mul(o.y.add(o.x));
        let c = self.t.mul(d2).mul(o.t);
        let dd = self.z.add(self.z).mul(o.z);
        let e = b.sub(a);
        let f = dd.sub(c);
        let g = dd.add(c);
        let h = b.add(a);
        Point {
            x: e.mul(f),
            y: g.mul(h),
            t: e.mul(h),
            z: f.mul(g),
        }
    }

    fn neg(self) -> Point {
        Point {
            x: self.x.neg(),
            y: self.y,
            z: self.z,
            t: self.t.neg(),
        }
    }

    fn select(a: Point, b: Point, pick: bool) -> Point {
        Point {
            x: Fe::select(a.x, b.x, pick),
            y: Fe::select(a.y, b.y, pick),
            z: Fe::select(a.z, b.z, pick),
            t: Fe::select(a.t, b.t, pick),
        }
    }

    /// [k]self, k as 32 little-endian bytes: the same work for every k.
    fn mul(self, k: &[u8; 32]) -> Point {
        let d2 = d().add(d());
        let mut q = Point::identity();
        for i in (0..256).rev() {
            q = q.add(q, d2);
            let sum = q.add(self, d2);
            q = Point::select(q, sum, (k[i / 8] >> (i % 8)) & 1 == 1);
        }
        q
    }

    fn encode(self) -> [u8; 32] {
        let zinv = self.z.invert();
        let x = self.x.mul(zinv);
        let y = self.y.mul(zinv);
        let mut out = y.to_bytes();
        out[31] |= (x.is_negative() as u8) << 7;
        out
    }

    /// A point from its 32 bytes, as OpenSSL's ge_frombytes_vartime reads
    /// it; None when there is no such point.
    fn decode(b: &[u8; 32]) -> Option<Point> {
        let y = Fe::from_bytes(b);
        let yy = y.square();
        let u = yy.sub(Fe::ONE);
        let v = d().mul(yy).add(Fe::ONE);
        let v3 = v.square().mul(v);
        let v7 = v3.square().mul(v);
        let mut e = [0xffu8; 32];
        e[0] = 0xfd;
        e[31] = 0x0f;
        let mut x = u.mul(v3).mul(u.mul(v7).pow(&e));
        let vxx = v.mul(x.square());
        if !vxx.sub(u).is_zero() {
            if !vxx.add(u).is_zero() {
                return None;
            }
            x = x.mul(sqrt_m1());
        }
        if x.is_negative() != (b[31] >> 7 == 1) {
            x = x.neg();
        }
        Some(Point {
            x,
            y,
            z: Fe::ONE,
            t: x.mul(y),
        })
    }

    fn base() -> Point {
        let mut b = [0x66u8; 32];
        b[0] = 0x58;
        Point::decode(&b).expect("the base point decodes")
    }
}

// --- Scalars mod L -------------------------------------------------------------

const L: [u64; 4] = [
    0x5812631a5cf5d3ed,
    0x14def9dea2f79cd6,
    0x0000000000000000,
    0x1000000000000000,
];

fn geq(a: &[u64; 4], b: &[u64; 4]) -> bool {
    for i in (0..4).rev() {
        if a[i] != b[i] {
            return a[i] > b[i];
        }
    }
    true
}

fn sub_in_place(a: &mut [u64; 4], b: &[u64; 4]) {
    let mut borrow = 0u64;
    for i in 0..4 {
        let (d1, b1) = a[i].overflowing_sub(b[i]);
        let (d2, b2) = d1.overflowing_sub(borrow);
        a[i] = d2;
        borrow = (b1 || b2) as u64;
    }
}

/// A little-endian number of any length, mod L, as 32 bytes.
fn reduce(bytes: &[u8]) -> [u8; 32] {
    let mut r = [0u64; 4];
    for i in (0..bytes.len() * 8).rev() {
        let bit = (bytes[i / 8] >> (i % 8)) & 1;
        // r = 2r + bit; r < L < 2^253 keeps it in 256 bits.
        for k in (1..4).rev() {
            r[k] = (r[k] << 1) | (r[k - 1] >> 63);
        }
        r[0] = (r[0] << 1) | bit as u64;
        if geq(&r, &L) {
            sub_in_place(&mut r, &L);
        }
    }
    let mut out = [0u8; 32];
    for (i, w) in r.iter().enumerate() {
        out[8 * i..8 * i + 8].copy_from_slice(&w.to_le_bytes());
    }
    out
}

fn words(b: &[u8; 32]) -> [u64; 4] {
    let mut w = [0u64; 4];
    for (i, x) in w.iter_mut().enumerate() {
        *x = load8(b, 8 * i);
    }
    w
}

/// (a * b + c) mod L.
fn mul_add(a: &[u8; 32], b: &[u8; 32], c: &[u8; 32]) -> [u8; 32] {
    let (a, b, c) = (words(a), words(b), words(c));
    let mut wide = [0u128; 9];
    for i in 0..4 {
        for j in 0..4 {
            let p = a[i] as u128 * b[j] as u128;
            wide[i + j] += p & 0xffff_ffff_ffff_ffff;
            wide[i + j + 1] += p >> 64;
        }
    }
    for (i, x) in c.iter().enumerate() {
        wide[i] += *x as u128;
    }
    let mut out = [0u8; 72];
    let mut carry = 0u128;
    for (i, w) in wide.iter().enumerate() {
        let v = w + carry;
        out[8 * i..8 * i + 8].copy_from_slice(&(v as u64).to_le_bytes());
        carry = v >> 64;
    }
    reduce(&out)
}

fn below_l(s: &[u8]) -> bool {
    let mut b = [0u8; 32];
    b.copy_from_slice(&s[..32]);
    !geq(&words(&b), &L)
}

// --- The scheme -------------------------------------------------------------------

fn expand(seed: &[u8; 32]) -> ([u8; 32], [u8; 32]) {
    let h = sha512::digest(seed);
    let mut a = [0u8; 32];
    a.copy_from_slice(&h[..32]);
    a[0] &= 248;
    a[31] &= 127;
    a[31] |= 64;
    let mut prefix = [0u8; 32];
    prefix.copy_from_slice(&h[32..]);
    (a, prefix)
}

/// The public key of a 32-byte private key (its seed).
pub fn public_key(seed: &[u8; 32]) -> [u8; 32] {
    let (a, _) = expand(seed);
    Point::base().mul(&a).encode()
}

/// The 64-byte signature of `message`.
pub fn sign(seed: &[u8; 32], message: &[u8]) -> [u8; 64] {
    let (a, prefix) = expand(seed);
    let public = Point::base().mul(&a).encode();
    let r = reduce(&sha512::digest_parts(&[&prefix, message]));
    let big_r = Point::base().mul(&r).encode();
    let h = reduce(&sha512::digest_parts(&[&big_r, &public, message]));
    let s = mul_add(&h, &a, &r);
    let mut out = [0u8; 64];
    out[..32].copy_from_slice(&big_r);
    out[32..].copy_from_slice(&s);
    out
}

/// Whether `signature` is `public`'s signature of exactly `message`.
pub fn verify(public: &[u8; 32], message: &[u8], signature: &[u8; 64]) -> bool {
    if !below_l(&signature[32..]) {
        return false;
    }
    let a = match Point::decode(public) {
        Some(p) => p,
        None => return false,
    };
    let h = reduce(&sha512::digest_parts(&[&signature[..32], public, message]));
    let mut s = [0u8; 32];
    s.copy_from_slice(&signature[32..]);
    let d2 = d().add(d());
    let check = Point::base().mul(&s).add(a.neg().mul(&h), d2).encode();
    check[..] == signature[..32]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::{hex, unhex};

    fn arr<const N: usize>(h: &str) -> [u8; N] {
        unhex(h).unwrap().try_into().unwrap()
    }

    // RFC 8032, section 7.1, tests 1 to 3.
    const VECTORS: [(&str, &str, &str, &str); 3] = [
        (
            "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
            "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
            "",
            "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
        ),
        (
            "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
            "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
            "72",
            "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00",
        ),
        (
            "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
            "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
            "af82",
            "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a",
        ),
    ];

    #[test]
    fn rfc8032_vectors() {
        for (seed, public, message, sig) in VECTORS {
            let seed: [u8; 32] = arr(seed);
            let message = unhex(message).unwrap();
            assert_eq!(hex(&public_key(&seed)), public);
            let signature = sign(&seed, &message);
            assert_eq!(hex(&signature), sig);
            let public: [u8; 32] = arr(public);
            assert!(verify(&public, &message, &signature));
            let mut bad = signature;
            bad[10] ^= 1;
            assert!(!verify(&public, &message, &bad));
            assert!(!verify(&public, b"other", &signature));
        }
    }

    #[test]
    fn s_at_or_past_l_is_refused() {
        let (seed, public, _, sig) = VECTORS[0];
        let _ = seed;
        let public: [u8; 32] = arr(public);
        let mut signature: [u8; 64] = arr(sig);
        // S + L is the same scalar, but not canonical.
        let s: [u8; 32] = signature[32..].try_into().unwrap();
        let mut l = [0u8; 32];
        for (i, w) in L.iter().enumerate() {
            l[8 * i..8 * i + 8].copy_from_slice(&w.to_le_bytes());
        }
        let mut sum = [0u8; 32];
        let mut carry = 0u16;
        for i in 0..32 {
            let v = s[i] as u16 + l[i] as u16 + carry;
            sum[i] = v as u8;
            carry = v >> 8;
        }
        signature[32..].copy_from_slice(&sum);
        assert!(!verify(&public, b"", &signature));
    }

    #[test]
    fn scalar_reduction() {
        let mut l = [0u8; 32];
        for (i, w) in L.iter().enumerate() {
            l[8 * i..8 * i + 8].copy_from_slice(&w.to_le_bytes());
        }
        assert_eq!(reduce(&l), [0u8; 32]);
        let mut one = [0u8; 32];
        one[0] = 1;
        assert_eq!(mul_add(&one, &one, &[0u8; 32]), one);
    }
}
