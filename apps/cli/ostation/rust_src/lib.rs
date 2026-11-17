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
use std::time::Duration;

/// Fallback Sentry DSN for `ostation` when `SENTRY_DSN` is unset.
pub const DEFAULT_SENTRY_DSN: &str =
    "https://3bacdd14dd3bb4d326948b35048dfdb6@sentry-ingest.ipv1337.dev/16";

/// Maximum time dropping the Sentry guard may block on exit.
pub const SENTRY_SHUTDOWN_TIMEOUT: Duration = Duration::from_millis(500);

/// Resolves the Sentry DSN from `SENTRY_DSN`, falling back to [`DEFAULT_SENTRY_DSN`].
pub fn resolve_sentry_dsn() -> String {
    std::env::var("SENTRY_DSN")
        .ok()
        .unwrap_or_else(|| DEFAULT_SENTRY_DSN.to_string())
}

/// Initializes fail-open, non-blocking Sentry error tracking.
///
/// Never panics on invalid or empty DSNs and caps shutdown flush at 500ms so
/// CLI exit never stalls when Sentry is unreachable.
pub fn init_sentry(dsn: &str) -> sentry::ClientInitGuard {
    sentry::init((
        dsn,
        sentry::ClientOptions {
            release: sentry::release_name!(),
            shutdown_timeout: SENTRY_SHUTDOWN_TIMEOUT,
            ..Default::default()
        },
    ))
}

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
