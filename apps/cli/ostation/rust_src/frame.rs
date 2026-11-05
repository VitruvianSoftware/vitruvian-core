// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! 6699 framing: encrypt/decrypt and a stream reader that tolerates padding.
//!
//! ```text
//! prefix(4) 0x00006699 | unknown(2) 0 | seqno(4) | cmd(4) | length(4)
//! payload: [12B GCM IV][ciphertext][16B tag]   (length = 12 + ct + 16)
//! suffix(4) 0x00009966
//! ```
//! AAD is header bytes 4..18, i.e. everything after the prefix.

use crate::{Error, Key, Result};
use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes128Gcm, Nonce};
use std::io::Read;

pub const PREFIX: [u8; 4] = [0x00, 0x00, 0x66, 0x99];
pub const SUFFIX: [u8; 4] = [0x00, 0x00, 0x99, 0x66];
pub const HEADER_LEN: usize = 18;
const IV_LEN: usize = 12;
const TAG_LEN: usize = 16;
/// Refuse absurd lengths from a misparsed stream rather than allocating them.
const MAX_PAYLOAD: usize = 64 * 1024;

#[derive(Debug, PartialEq, Eq)]
pub struct Frame {
    pub seqno: u32,
    pub cmd: u32,
    pub payload: Vec<u8>,
}

fn aad(seqno: u32, cmd: u32, length: u32) -> [u8; 14] {
    let mut a = [0u8; 14];
    a[2..6].copy_from_slice(&seqno.to_be_bytes());
    a[6..10].copy_from_slice(&cmd.to_be_bytes());
    a[10..14].copy_from_slice(&length.to_be_bytes());
    a
}

/// AES-128-GCM seal; returns ciphertext || tag.
pub fn gcm_seal(key: &Key, iv: &[u8; IV_LEN], plaintext: &[u8], aad: &[u8]) -> Vec<u8> {
    Aes128Gcm::new(key.into())
        .encrypt(
            Nonce::from_slice(iv),
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .expect("AES-GCM encryption cannot fail for in-memory buffers")
}

/// Builds a frame with a caller-chosen IV (deterministic, for tests).
pub fn pack_frame_with_iv(
    seqno: u32,
    cmd: u32,
    raw: &[u8],
    key: &Key,
    iv: [u8; IV_LEN],
) -> Vec<u8> {
    let length = (IV_LEN + raw.len() + TAG_LEN) as u32;
    let sealed = gcm_seal(key, &iv, raw, &aad(seqno, cmd, length));
    let mut out = Vec::with_capacity(HEADER_LEN + length as usize + SUFFIX.len());
    out.extend_from_slice(&PREFIX);
    out.extend_from_slice(&aad(seqno, cmd, length));
    out.extend_from_slice(&iv);
    out.extend_from_slice(&sealed);
    out.extend_from_slice(&SUFFIX);
    out
}

/// Builds a frame with a random IV.
pub fn pack_frame(seqno: u32, cmd: u32, raw: &[u8], key: &Key) -> Result<Vec<u8>> {
    let mut iv = [0u8; IV_LEN];
    getrandom::getrandom(&mut iv).map_err(|e| Error::Protocol(format!("no randomness: {e}")))?;
    Ok(pack_frame_with_iv(seqno, cmd, raw, key, iv))
}

/// Decrypts one frame's payload given its header fields.
pub fn open_payload(key: &Key, seqno: u32, cmd: u32, length: u32, enc: &[u8]) -> Result<Vec<u8>> {
    if enc.len() < IV_LEN + TAG_LEN {
        return Err(Error::Protocol(format!("payload too short: {}", enc.len())));
    }
    let (iv, ct_and_tag) = enc.split_at(IV_LEN);
    Aes128Gcm::new(key.into())
        .decrypt(
            Nonce::from_slice(iv),
            Payload {
                msg: ct_and_tag,
                aad: &aad(seqno, cmd, length),
            },
        )
        .map_err(|_| Error::Auth(format!("GCM tag mismatch (cmd {cmd}, seqno {seqno})")))
}

/// The charger drops frames it cannot decrypt without answering, so a read
/// timeout is the symptom of a wrong localKey or of another session (the Olight
/// app) holding the charger.
fn io_error(e: std::io::Error) -> Error {
    match e.kind() {
        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut => Error::Protocol(
            "no reply from the charger: wrong localKey, or the Olight app is connected (force-stop it)"
                .into(),
        ),
        _ => Error::Io(e),
    }
}

/// Reads frames from any byte stream.
pub struct FrameReader<R: Read> {
    inner: R,
}

impl<R: Read> FrameReader<R> {
    pub fn new(inner: R) -> Self {
        Self { inner }
    }

    fn byte(&mut self) -> Result<u8> {
        let mut b = [0u8; 1];
        self.inner.read_exact(&mut b).map_err(|e| match e.kind() {
            std::io::ErrorKind::UnexpectedEof => Error::Protocol("socket closed".into()),
            _ => io_error(e),
        })?;
        Ok(b[0])
    }

    fn exact(&mut self, n: usize) -> Result<Vec<u8>> {
        let mut v = vec![0u8; n];
        self.inner.read_exact(&mut v).map_err(|e| match e.kind() {
            std::io::ErrorKind::UnexpectedEof => Error::Protocol("socket closed mid-frame".into()),
            _ => io_error(e),
        })?;
        Ok(v)
    }

    /// Finds the next prefix. The device interleaves zero padding of varying
    /// length (2 or 6 bytes seen), so slide a 4-byte window one byte at a time
    /// and accept only zeros as the bytes that fall out of it.
    fn sync(&mut self) -> Result<()> {
        let mut win = [0u8; 4];
        for slot in win.iter_mut() {
            *slot = self.byte()?;
        }
        while win != PREFIX {
            if win[0] != 0 {
                return Err(Error::Protocol(format!(
                    "unexpected stream bytes: {win:02x?}"
                )));
            }
            win.rotate_left(1);
            win[3] = self.byte()?;
        }
        Ok(())
    }

    /// Reads and decrypts the next frame with `key`.
    pub fn read_frame(&mut self, key: &Key) -> Result<Frame> {
        self.sync()?;
        let h = self.exact(HEADER_LEN - PREFIX.len())?;
        let seqno = u32::from_be_bytes(h[2..6].try_into().unwrap());
        let cmd = u32::from_be_bytes(h[6..10].try_into().unwrap());
        let length = u32::from_be_bytes(h[10..14].try_into().unwrap());
        if length as usize > MAX_PAYLOAD {
            return Err(Error::Protocol(format!("frame length {length} too large")));
        }
        let body = self.exact(length as usize + SUFFIX.len())?;
        let (enc, suffix) = body.split_at(length as usize);
        if suffix != SUFFIX {
            return Err(Error::Protocol("bad suffix".into()));
        }
        let payload = open_payload(key, seqno, cmd, length, enc)?;
        Ok(Frame {
            seqno,
            cmd,
            payload,
        })
    }
}
