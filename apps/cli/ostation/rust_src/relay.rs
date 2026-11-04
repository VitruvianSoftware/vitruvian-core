// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! TCP relay 127.0.0.1:<listen> -> adb -> phone nc -> charger.
//!
//! For hosts that cannot reach LAN IPs directly (this Mac's sockets got
//! EHOSTUNREACH while nc and ping worked): the phone, which is on the LAN,
//! forwards the bytes.

use crate::Result;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::process::{Command, Stdio};
use std::thread;

pub struct RelayConfig {
    pub listen: String,
    pub target_host: String,
    pub target_port: u16,
    /// `adb -s <serial>`; None uses the only attached device.
    pub adb_serial: Option<String>,
}

pub fn adb_args(c: &RelayConfig) -> Vec<String> {
    let mut a = Vec::new();
    if let Some(s) = &c.adb_serial {
        a.push("-s".to_string());
        a.push(s.clone());
    }
    a.extend(["shell", "-T", "toybox", "nc"].map(String::from));
    a.push(c.target_host.clone());
    a.push(c.target_port.to_string());
    a
}

/// Serves one client at a time, forever.
pub fn run(c: &RelayConfig) -> Result<()> {
    let listener = TcpListener::bind(&c.listen)?;
    eprintln!("relay listening on {}", c.listen);
    for client in listener.incoming() {
        let client = client?;
        eprintln!("client connected");
        if let Err(e) = serve(c, client) {
            eprintln!("session error: {e}");
        }
        eprintln!("session ended");
    }
    Ok(())
}

fn serve(c: &RelayConfig, client: TcpStream) -> Result<()> {
    let mut adb = Command::new("adb")
        .args(adb_args(c))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()?;
    let mut to_dev = adb.stdin.take().expect("piped stdin");
    let mut from_dev = adb.stdout.take().expect("piped stdout");
    let mut client_rx = client.try_clone()?;
    let mut client_tx = client.try_clone()?;

    let up = thread::spawn(move || pump(&mut client_rx, &mut to_dev));
    let down = thread::spawn(move || pump(&mut from_dev, &mut client_tx));
    // Either side closing ends the session.
    let _ = up.join();
    let _ = adb.kill();
    let _ = down.join();
    let _ = client.shutdown(std::net::Shutdown::Both);
    let _ = adb.wait();
    Ok(())
}

fn pump(src: &mut impl Read, dst: &mut impl Write) {
    let mut buf = [0u8; 4096];
    while let Ok(n) = src.read(&mut buf) {
        if n == 0 || dst.write_all(&buf[..n]).and_then(|_| dst.flush()).is_err() {
            break;
        }
    }
}
