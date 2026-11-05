// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! One-shot status query: connect, negotiate, ask for DPS.

use crate::frame::{pack_frame, FrameReader};
use crate::session::negotiate;
use crate::{Error, Key, Result};
use std::io::Write;
use std::net::TcpStream;
use std::time::Duration;

pub const CMD_HEARTBEAT: u32 = 9;
pub const CMD_STATUS: u32 = 16;
pub const DEFAULT_PORT: u16 = 6668;
const TIMEOUT: Duration = Duration::from_secs(10);

/// Connects to the charger and returns its status JSON (`{"dps": {...}}`).
///
/// The charger serves one LAN session at a time: stop the Olight app first, or
/// it silently ignores this client.
pub fn fetch_status(host: &str, port: u16, local_key: &Key) -> Result<serde_json::Value> {
    let mut stream = connect(host, port)?;
    let mut reader = FrameReader::new(stream.try_clone()?);
    let session_key = negotiate(&mut reader, &mut stream, local_key)?;

    stream.write_all(&pack_frame(3, CMD_STATUS, b"{}", &session_key)?)?;
    loop {
        let f = reader.read_frame(&session_key)?;
        if f.cmd == CMD_HEARTBEAT {
            continue;
        }
        if f.cmd != CMD_STATUS {
            return Err(Error::Protocol(format!(
                "expected status cmd 16, got {}",
                f.cmd
            )));
        }
        return parse_status(&f.payload);
    }
}

/// The status reply is a 4-byte retcode followed by JSON.
pub fn parse_status(payload: &[u8]) -> Result<serde_json::Value> {
    let body = payload
        .get(4..)
        .ok_or_else(|| Error::Protocol("status payload shorter than its retcode".into()))?;
    serde_json::from_slice(body).map_err(|e| Error::Protocol(format!("status is not JSON: {e}")))
}

fn connect(host: &str, port: u16) -> Result<TcpStream> {
    use std::net::ToSocketAddrs;
    let addr = (host, port)
        .to_socket_addrs()?
        .next()
        .ok_or_else(|| Error::Usage(format!("cannot resolve {host}")))?;
    let s = TcpStream::connect_timeout(&addr, TIMEOUT)?;
    s.set_read_timeout(Some(TIMEOUT))?;
    s.set_write_timeout(Some(TIMEOUT))?;
    Ok(s)
}
