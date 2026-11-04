// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Session-key negotiation (cmds 3 -> 4 -> 5), encrypted with the localKey.

use crate::frame::{gcm_seal, pack_frame, FrameReader};
use crate::{Error, Key, Result};
use hmac::{Hmac, Mac};
use sha2::Sha256;
use std::io::{Read, Write};

pub const CMD_SESS_KEY_START: u32 = 3;
pub const CMD_SESS_KEY_RESP: u32 = 4;
pub const CMD_SESS_KEY_FINISH: u32 = 5;

pub fn hmac_sha256(key: &Key, data: &[u8]) -> [u8; 32] {
    let mut m = <Hmac<Sha256> as Mac>::new_from_slice(key).expect("HMAC accepts any key length");
    m.update(data);
    m.finalize().into_bytes().into()
}

/// session key = first 16 bytes of
/// AES-GCM(localKey, iv = local_nonce[..12]).encrypt(local_nonce XOR remote_nonce).
pub fn derive_session_key(local_key: &Key, local_nonce: &[u8; 16], remote_nonce: &[u8; 16]) -> Key {
    let mut xored = [0u8; 16];
    for i in 0..16 {
        xored[i] = local_nonce[i] ^ remote_nonce[i];
    }
    let iv: [u8; 12] = local_nonce[..12].try_into().unwrap();
    let sealed = gcm_seal(local_key, &iv, &xored, &[]);
    sealed[..16].try_into().unwrap()
}

/// Runs the handshake with a caller-chosen nonce (deterministic, for tests).
/// `reader` and `writer` are the two halves of one connection. Uses seqno 1 and
/// 2; the caller continues from 3.
pub fn negotiate_with_nonce<R: Read, W: Write>(
    reader: &mut FrameReader<R>,
    writer: &mut W,
    local_key: &Key,
    local_nonce: [u8; 16],
) -> Result<Key> {
    writer.write_all(&pack_frame(1, CMD_SESS_KEY_START, &local_nonce, local_key)?)?;
    let resp = reader.read_frame(local_key)?;
    if resp.cmd != CMD_SESS_KEY_RESP {
        return Err(Error::Protocol(format!("expected cmd 4, got {}", resp.cmd)));
    }
    let pt = resp.payload;
    if pt.len() < 52 {
        return Err(Error::Protocol(format!(
            "step-2 payload is {} bytes, want 52",
            pt.len()
        )));
    }
    if pt[..4] != [0, 0, 0, 0] {
        return Err(Error::Protocol(format!("step-2 retcode {:02x?}", &pt[..4])));
    }
    let remote_nonce: [u8; 16] = pt[4..20].try_into().unwrap();
    // This HMAC is the proof that the device holds the same localKey.
    if hmac_sha256(local_key, &local_nonce)[..] != pt[20..52] {
        return Err(Error::Auth("device HMAC mismatch (wrong localKey?)".into()));
    }
    let finish = hmac_sha256(local_key, &remote_nonce);
    writer.write_all(&pack_frame(2, CMD_SESS_KEY_FINISH, &finish, local_key)?)?;
    Ok(derive_session_key(local_key, &local_nonce, &remote_nonce))
}

/// Runs the handshake with a random nonce.
pub fn negotiate<R: Read, W: Write>(
    reader: &mut FrameReader<R>,
    writer: &mut W,
    local_key: &Key,
) -> Result<Key> {
    let mut nonce = [0u8; 16];
    getrandom::getrandom(&mut nonce).map_err(|e| Error::Protocol(format!("no randomness: {e}")))?;
    negotiate_with_nonce(reader, writer, local_key, nonce)
}
