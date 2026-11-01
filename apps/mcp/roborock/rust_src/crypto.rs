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
// SPDX-License-Identifier: MIT

//! The cryptographic primitives the Roborock protocol is built on.
//!
//! Every primitive comes from a vetted crate (RustCrypto, getrandom); this
//! module only arranges them the way python-roborock 7.12.1's
//! `roborock/protocol.py` and `web_api.py` do: AES-128 in ECB and CBC with
//! PKCS#7 padding, AES-256-GCM for the L01 local protocol, MD5, SHA-256,
//! HMAC-SHA256, CRC32 and gzip.

use aes::cipher::generic_array::GenericArray;
use aes::cipher::{BlockDecrypt, BlockEncrypt, KeyInit};
use aes::Aes128;
use aes_gcm::aead::{Aead, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::Engine;
use hmac::{Hmac, Mac};
use md5::{Digest, Md5};
use sha2::Sha256;
use std::io::Read;

const BLOCK: usize = 16;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CryptoError(pub String);

impl std::fmt::Display for CryptoError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for CryptoError {}

pub fn md5(data: &[u8]) -> [u8; 16] {
    let mut hasher = Md5::new();
    hasher.update(data);
    hasher.finalize().into()
}

pub fn md5_hex(data: &[u8]) -> String {
    hex(&md5(data))
}

pub fn sha256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hasher.finalize().into()
}

pub fn hmac_sha256(key: &[u8], data: &[u8]) -> [u8; 32] {
    // HMAC accepts a key of any length, so this cannot fail.
    let mut mac = <Hmac<Sha256> as Mac>::new_from_slice(key).expect("HMAC takes any key length");
    mac.update(data);
    mac.finalize().into_bytes().into()
}

pub fn crc32(data: &[u8]) -> u32 {
    crc32fast::hash(data)
}

pub fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub fn b64(bytes: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

/// `secrets.token_urlsafe(n)`: n random bytes, URL-safe base64 without padding.
pub fn token_urlsafe(n: usize) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(random_bytes(n))
}

pub fn random_bytes(n: usize) -> Vec<u8> {
    let mut buf = vec![0u8; n];
    getrandom::getrandom(&mut buf).expect("the operating system's random source failed");
    buf
}

/// A random string of ASCII letters and digits (the `x-mercy-ks` login nonce).
pub fn random_alphanumeric(n: usize) -> String {
    const ALPHABET: &[u8] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    random_bytes(n)
        .into_iter()
        // 256 is not a multiple of 62; the slight bias is irrelevant for a nonce.
        .map(|b| ALPHABET[(b as usize) % ALPHABET.len()] as char)
        .collect()
}

fn pkcs7_pad(data: &[u8]) -> Vec<u8> {
    let pad = BLOCK - data.len() % BLOCK;
    let mut out = data.to_vec();
    out.extend(std::iter::repeat(pad as u8).take(pad));
    out
}

fn pkcs7_unpad(mut data: Vec<u8>) -> Result<Vec<u8>, CryptoError> {
    let bad = || CryptoError("Padding is incorrect.".to_string());
    let pad = *data.last().ok_or_else(bad)? as usize;
    if pad == 0 || pad > BLOCK || pad > data.len() {
        return Err(bad());
    }
    if !data[data.len() - pad..].iter().all(|&b| b as usize == pad) {
        return Err(bad());
    }
    data.truncate(data.len() - pad);
    Ok(data)
}

fn aes128(key: &[u8]) -> Result<Aes128, CryptoError> {
    if key.len() != 16 {
        return Err(CryptoError("Wrong token length".to_string()));
    }
    Ok(Aes128::new(GenericArray::from_slice(key)))
}

/// `Utils.encrypt_ecb`: an empty plaintext stays empty, anything else is padded.
pub fn encrypt_ecb(plaintext: &[u8], key: &[u8]) -> Result<Vec<u8>, CryptoError> {
    let cipher = aes128(key)?;
    if plaintext.is_empty() {
        return Ok(Vec::new());
    }
    let mut data = pkcs7_pad(plaintext);
    for chunk in data.chunks_mut(BLOCK) {
        cipher.encrypt_block(GenericArray::from_mut_slice(chunk));
    }
    Ok(data)
}

pub fn decrypt_ecb(ciphertext: &[u8], key: &[u8]) -> Result<Vec<u8>, CryptoError> {
    if ciphertext.is_empty() {
        return Ok(Vec::new());
    }
    let cipher = aes128(key)?;
    if ciphertext.len() % BLOCK != 0 {
        return Err(CryptoError(
            "Data must be aligned to block boundary in ECB mode".to_string(),
        ));
    }
    let mut data = ciphertext.to_vec();
    for chunk in data.chunks_mut(BLOCK) {
        cipher.decrypt_block(GenericArray::from_mut_slice(chunk));
    }
    pkcs7_unpad(data)
}

/// `Utils.encrypt_cbc` with the zero IV the protocol uses.
pub fn encrypt_cbc(plaintext: &[u8], key: &[u8]) -> Result<Vec<u8>, CryptoError> {
    let cipher = aes128(key)?;
    if plaintext.is_empty() {
        return Ok(Vec::new());
    }
    let mut data = pkcs7_pad(plaintext);
    let mut prev = [0u8; BLOCK];
    for chunk in data.chunks_mut(BLOCK) {
        for (b, p) in chunk.iter_mut().zip(prev.iter()) {
            *b ^= p;
        }
        cipher.encrypt_block(GenericArray::from_mut_slice(chunk));
        prev.copy_from_slice(chunk);
    }
    Ok(data)
}

/// `Utils.decrypt_cbc` with the zero IV the protocol uses (map responses).
pub fn decrypt_cbc(ciphertext: &[u8], key: &[u8]) -> Result<Vec<u8>, CryptoError> {
    if ciphertext.is_empty() {
        return Ok(Vec::new());
    }
    let cipher = aes128(key)?;
    if ciphertext.len() % BLOCK != 0 {
        return Err(CryptoError(
            "Data must be aligned to block boundary in CBC mode".to_string(),
        ));
    }
    let mut data = ciphertext.to_vec();
    let mut prev = [0u8; BLOCK];
    for chunk in data.chunks_mut(BLOCK) {
        let mut this = [0u8; BLOCK];
        this.copy_from_slice(chunk);
        cipher.decrypt_block(GenericArray::from_mut_slice(chunk));
        for (b, p) in chunk.iter_mut().zip(prev.iter()) {
            *b ^= p;
        }
        prev = this;
    }
    pkcs7_unpad(data)
}

/// AES-256-GCM; the returned bytes are the ciphertext followed by the 16-byte tag.
pub fn encrypt_gcm(key: &[u8; 32], iv: &[u8; 12], aad: &[u8], plaintext: &[u8]) -> Vec<u8> {
    let cipher = Aes256Gcm::new(GenericArray::from_slice(key));
    cipher
        .encrypt(
            Nonce::from_slice(iv),
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .expect("AES-GCM encryption of an in-memory buffer cannot fail")
}

pub fn decrypt_gcm(
    key: &[u8; 32],
    iv: &[u8; 12],
    aad: &[u8],
    payload: &[u8],
) -> Result<Vec<u8>, CryptoError> {
    if payload.len() < 16 {
        return Err(CryptoError(
            "Invalid payload length for GCM decryption".to_string(),
        ));
    }
    let cipher = Aes256Gcm::new(GenericArray::from_slice(key));
    cipher
        .decrypt(Nonce::from_slice(iv), Payload { msg: payload, aad })
        .map_err(|_| CryptoError("GCM tag verification failed".to_string()))
}

pub fn gunzip(data: &[u8]) -> Result<Vec<u8>, CryptoError> {
    let mut out = Vec::new();
    flate2::read::MultiGzDecoder::new(data)
        .read_to_end(&mut out)
        .map_err(|e| CryptoError(format!("Failed to decompress: {e}")))?;
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn md5_matches_the_reference_vector() {
        assert_eq!(md5_hex(b"abc"), "900150983cd24fb0d6963f7d28e17f72");
    }

    #[test]
    fn hmac_matches_rfc_4231_case_2() {
        let mac = hmac_sha256(b"Jefe", b"what do ya want for nothing?");
        assert_eq!(
            hex(&mac),
            "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
        );
    }

    #[test]
    fn ecb_matches_fips_197_and_round_trips() {
        // FIPS-197 C.1: one block, no padding involved in the first 16 bytes.
        let key: Vec<u8> = (0u8..16).collect();
        let pt: [u8; 16] = [
            0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd,
            0xee, 0xff,
        ];
        let ct = encrypt_ecb(&pt, &key).unwrap();
        assert_eq!(hex(&ct[..16]), "69c4e0d86a7b0430d8cdb78070b4c55a");
        assert_eq!(ct.len(), 32, "a full block of PKCS#7 padding follows");
        assert_eq!(decrypt_ecb(&ct, &key).unwrap(), pt);
        assert!(encrypt_ecb(b"", &key).unwrap().is_empty());
        assert!(encrypt_ecb(b"x", b"short").is_err());
    }

    #[test]
    fn cbc_round_trips_and_chains_blocks() {
        let key = [7u8; 16];
        let pt = b"two identical blocks...two identical blocks...";
        let ct = encrypt_cbc(pt, &key).unwrap();
        // ECB would repeat; CBC must not.
        assert_ne!(ct[0..16], ct[16..32]);
        assert_eq!(decrypt_cbc(&ct, &key).unwrap(), pt);
        assert!(decrypt_cbc(&ct[..15], &key).is_err());
    }

    #[test]
    fn gcm_round_trips_and_rejects_tampering() {
        let key = [1u8; 32];
        let iv = [2u8; 12];
        let mut sealed = encrypt_gcm(&key, &iv, b"aad", b"hello");
        assert_eq!(decrypt_gcm(&key, &iv, b"aad", &sealed).unwrap(), b"hello");
        assert!(decrypt_gcm(&key, &iv, b"other", &sealed).is_err());
        sealed[0] ^= 1;
        assert!(decrypt_gcm(&key, &iv, b"aad", &sealed).is_err());
    }

    #[test]
    fn bad_padding_is_an_error_not_a_panic() {
        let key = [3u8; 16];
        let mut ct = encrypt_ecb(b"0123456789abcdef", &key).unwrap();
        let n = ct.len();
        ct[n - 1] ^= 0xff;
        assert!(decrypt_ecb(&ct, &key).is_err());
    }
}
