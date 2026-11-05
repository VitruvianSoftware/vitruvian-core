// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Local client for the Olight Ostation 2 Pro charger.
//!
//! The charger speaks Tuya LAN protocol 3.5 with one deviation: its 6699 frame
//! header is 18 bytes, not the 20 that stock libraries (tinytuya) assume. See
//! README.md for the wire format.

pub mod client;
pub mod frame;
pub mod relay;
pub mod session;

use std::fmt;

/// A 16-byte AES-128 key: the device localKey or a derived session key.
pub type Key = [u8; 16];

#[derive(Debug)]
pub enum Error {
    Io(std::io::Error),
    /// The peer sent something the protocol does not allow.
    Protocol(String),
    /// A GCM tag or the key-negotiation HMAC did not verify.
    Auth(String),
    /// Bad user input, e.g. a localKey that is not 16 bytes.
    Usage(String),
}

pub type Result<T> = std::result::Result<T, Error>;

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Io(e) => write!(f, "i/o error: {e}"),
            Error::Protocol(m) => write!(f, "protocol error: {m}"),
            Error::Auth(m) => write!(f, "authentication failed: {m}"),
            Error::Usage(m) => write!(f, "{m}"),
        }
    }
}

impl std::error::Error for Error {}

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Error::Io(e)
    }
}

/// Parses a localKey given as 16 ASCII bytes.
pub fn parse_key(s: &str) -> Result<Key> {
    s.as_bytes()
        .try_into()
        .map_err(|_| Error::Usage(format!("localKey must be 16 bytes, got {}", s.len())))
}

#[cfg(test)]
mod tests;
