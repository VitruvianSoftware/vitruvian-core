// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Offline tests: no charger needed.

use crate::frame::{pack_frame, pack_frame_with_iv, FrameReader, HEADER_LEN, PREFIX, SUFFIX};
use crate::session::{derive_session_key, hmac_sha256, negotiate};
use crate::{client, parse_key, Error, Key};
use std::io::{Cursor, Write};
use std::net::{TcpListener, TcpStream};
use std::thread;

/// The LAN-only key the committed capture was recorded with.
const KEY: &Key = b"^Jm[8&31gvy=XHu0";

fn read_one(bytes: &[u8], key: &Key) -> crate::Result<crate::frame::Frame> {
    FrameReader::new(Cursor::new(bytes.to_vec())).read_frame(key)
}

#[test]
fn header_is_18_bytes_and_carries_fields() {
    let f = pack_frame_with_iv(7, 16, b"{}", KEY, [9; 12]);
    assert_eq!(f[..4], PREFIX);
    assert_eq!(f[4..6], [0, 0]);
    assert_eq!(u32::from_be_bytes(f[6..10].try_into().unwrap()), 7);
    assert_eq!(u32::from_be_bytes(f[10..14].try_into().unwrap()), 16);
    let length = u32::from_be_bytes(f[14..18].try_into().unwrap()) as usize;
    assert_eq!(length, f.len() - HEADER_LEN - SUFFIX.len());
    assert_eq!(
        length,
        12 + 2 + 16,
        "status request is 30 payload bytes on the wire"
    );
    assert_eq!(f[f.len() - 4..], SUFFIX);
}

#[test]
fn frame_round_trips() {
    let f = pack_frame(3, 16, br#"{"dps":{}}"#, KEY).unwrap();
    let got = read_one(&f, KEY).unwrap();
    assert_eq!(
        (got.seqno, got.cmd, got.payload.as_slice()),
        (3, 16, &br#"{"dps":{}}"#[..])
    );
}

#[test]
fn zero_padding_of_any_length_is_skipped() {
    // 2 and 6 bytes both appear in the real capture; 2 is the case a
    // 4-bytes-at-a-time scanner misaligns on.
    for pad in [0usize, 1, 2, 3, 5, 6, 9] {
        let mut s = vec![0u8; pad];
        s.extend(pack_frame(4, 9, b"", KEY).unwrap());
        let got = read_one(&s, KEY).unwrap();
        assert_eq!((got.cmd, got.payload.len()), (9, 0), "pad {pad}");
    }
}

#[test]
fn non_zero_garbage_is_rejected() {
    let mut s = vec![0x41, 0x42];
    s.extend(pack_frame(4, 9, b"", KEY).unwrap());
    assert!(matches!(read_one(&s, KEY), Err(Error::Protocol(_))));
}

#[test]
fn tampered_header_fails_authentication() {
    let mut f = pack_frame(5, 16, b"{}", KEY).unwrap();
    f[9] ^= 1; // seqno is part of the AAD
    assert!(matches!(read_one(&f, KEY), Err(Error::Auth(_))));
}

#[test]
fn wrong_key_fails_authentication() {
    let f = pack_frame(5, 16, b"{}", KEY).unwrap();
    assert!(matches!(
        read_one(&f, b"0123456789abcdef"),
        Err(Error::Auth(_))
    ));
}

#[test]
fn truncated_stream_is_an_error_not_a_hang() {
    let f = pack_frame(5, 16, b"{}", KEY).unwrap();
    assert!(read_one(&f[..f.len() - 6], KEY).is_err());
}

#[test]
fn oversized_length_is_refused() {
    let mut f = pack_frame(5, 16, b"{}", KEY).unwrap();
    f[14..18].copy_from_slice(&u32::MAX.to_be_bytes());
    assert!(matches!(read_one(&f, KEY), Err(Error::Protocol(_))));
}

#[test]
fn key_must_be_16_bytes() {
    assert!(parse_key("^Jm[8&31gvy=XHu0").is_ok());
    assert!(matches!(parse_key("short"), Err(Error::Usage(_))));
}

/// A minimal charger: answers the handshake, then a status request.
fn fake_device(listener: TcpListener, key: Key, hmac_key: Key) -> thread::JoinHandle<()> {
    thread::spawn(move || {
        let (mut s, _) = listener.accept().unwrap();
        let mut r = FrameReader::new(s.try_clone().unwrap());
        let start = r.read_frame(&key).unwrap();
        assert_eq!(start.cmd, 3);
        let local_nonce: [u8; 16] = start.payload.try_into().unwrap();
        let remote_nonce = *b"287799768a4a11c7";
        let mut resp = vec![0u8; 4];
        resp.extend(remote_nonce);
        resp.extend(hmac_sha256(&hmac_key, &local_nonce));
        s.write_all(&[0, 0, 0, 0, 0, 0]).unwrap(); // device padding
        s.write_all(&pack_frame(100, 4, &resp, &key).unwrap())
            .unwrap();
        let fin = r.read_frame(&key).unwrap();
        assert_eq!(fin.cmd, 5);
        assert_eq!(fin.payload, hmac_sha256(&key, &remote_nonce));
        let session = derive_session_key(&key, &local_nonce, &remote_nonce);
        let req = r.read_frame(&session).unwrap();
        assert_eq!((req.cmd, req.payload.as_slice()), (16, &b"{}"[..]));
        s.write_all(&pack_frame(101, 9, b"", &session).unwrap())
            .unwrap(); // heartbeat first
        let mut status = vec![0u8; 4];
        status.extend(br#"{"dps":{"101":false,"105":3}}"#);
        s.write_all(&pack_frame(102, 16, &status, &session).unwrap())
            .unwrap();
    })
}

#[test]
fn fetch_status_against_a_fake_device() {
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = l.local_addr().unwrap().port();
    let dev = fake_device(l, *KEY, *KEY);
    let status = client::fetch_status("127.0.0.1", port, KEY).unwrap();
    dev.join().unwrap();
    assert_eq!(status["dps"]["105"], 3);
}

#[test]
fn wrong_local_key_is_reported_as_an_auth_failure() {
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = l.local_addr().unwrap().port();
    // The device answers with an HMAC from a different key.
    let dev = thread::spawn(move || {
        let (mut s, _) = l.accept().unwrap();
        let mut r = FrameReader::new(s.try_clone().unwrap());
        let start = r.read_frame(KEY).unwrap();
        let nonce: [u8; 16] = start.payload.try_into().unwrap();
        let mut resp = vec![0u8; 4];
        resp.extend([7u8; 16]);
        resp.extend(hmac_sha256(b"0123456789abcdef", &nonce));
        s.write_all(&pack_frame(1, 4, &resp, KEY).unwrap()).unwrap();
    });
    let mut stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
    let mut reader = FrameReader::new(stream.try_clone().unwrap());
    let err = negotiate(&mut reader, &mut stream, KEY).unwrap_err();
    dev.join().unwrap();
    assert!(matches!(err, Error::Auth(_)), "{err}");
}

/// Splits a classic little-endian pcap into the two TCP byte streams, by whether
/// the segment came from the charger (port 6668). Returns (client, device).
fn pcap_streams(pcap: &[u8]) -> (Vec<u8>, Vec<u8>) {
    assert_eq!(pcap[..4], [0xd4, 0xc3, 0xb2, 0xa1], "little-endian pcap");
    let (mut client, mut device) = (Vec::new(), Vec::new());
    let mut o = 24;
    while o < pcap.len() {
        let incl = u32::from_le_bytes(pcap[o + 8..o + 12].try_into().unwrap()) as usize;
        let p = &pcap[o + 16..o + 16 + incl];
        o += 16 + incl;
        let ip = 14;
        let tcp = ip + (p[ip] & 15) as usize * 4;
        let off = (p[tcp + 12] >> 4) as usize * 4;
        let sport = u16::from_be_bytes([p[tcp], p[tcp + 1]]);
        let data = &p[tcp + off..];
        if sport == 6668 {
            &mut device
        } else {
            &mut client
        }
        .extend_from_slice(data);
    }
    (client, device)
}

#[test]
fn replays_the_real_olight_app_capture() {
    let (client, device) = pcap_streams(include_bytes!("../ost_app.pcap"));
    let mut c = FrameReader::new(Cursor::new(client));
    let mut d = FrameReader::new(Cursor::new(device));

    let start = c.read_frame(KEY).unwrap();
    assert_eq!(start.cmd, 3);
    let local_nonce: [u8; 16] = start.payload.try_into().unwrap();

    let resp = d.read_frame(KEY).unwrap();
    assert_eq!(resp.cmd, 4);
    assert_eq!(resp.payload[..4], [0, 0, 0, 0]);
    let remote_nonce: [u8; 16] = resp.payload[4..20].try_into().unwrap();
    assert_eq!(
        resp.payload[20..52],
        hmac_sha256(KEY, &local_nonce),
        "device proves the key"
    );

    let fin = c.read_frame(KEY).unwrap();
    assert_eq!(fin.cmd, 5);
    assert_eq!(fin.payload, hmac_sha256(KEY, &remote_nonce));

    // Everything after the handshake only decrypts with the derived key.
    let session = derive_session_key(KEY, &local_nonce, &remote_nonce);
    let req = c.read_frame(&session).unwrap();
    assert_eq!((req.cmd, req.payload.as_slice()), (16, &b"{}"[..]));

    let mut status = None;
    let mut heartbeats = 0;
    while let Ok(f) = d.read_frame(&session) {
        match f.cmd {
            16 => status = Some(client::parse_status(&f.payload).unwrap()),
            9 => heartbeats += 1,
            other => panic!("unexpected cmd {other}"),
        }
    }
    assert!(status.expect("status reply")["dps"].is_object());
    assert!(heartbeats > 0, "capture has device heartbeats");
    while let Ok(f) = c.read_frame(&session) {
        assert_eq!(f.cmd, 9);
    }
}

#[test]
fn a_silent_device_gets_an_actionable_error() {
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    let s = TcpStream::connect(l.local_addr().unwrap()).unwrap();
    s.set_read_timeout(Some(std::time::Duration::from_millis(50)))
        .unwrap();
    let _held_open = l.accept().unwrap();
    let err = FrameReader::new(s).read_frame(KEY).unwrap_err();
    assert!(err.to_string().contains("Olight app"), "{err}");
}
