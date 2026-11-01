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

//! The local TCP channel to a V1 vacuum (port 58867).
//!
//! A port of python-roborock 7.12.1's `devices/transport/local_channel.py`:
//! connect, say hello in the "1.0" protocol and then "L01", keep the session
//! alive with a ping every 10 seconds, and hand every decoded frame to the
//! subscriber. The caller correlates requests and responses.

use crate::protocol::{self, FrameBuffer, Message, NextInt, Nonces};
use std::io::{ErrorKind, Read, Write};
use std::net::{Shutdown, SocketAddr, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

pub const PORT: u16 = 58867;
const TIMEOUT: Duration = Duration::from_secs(5);
const PING_INTERVAL: Duration = Duration::from_secs(10);

static CONNECT_NONCE: NextInt = NextInt::new(10_000, 32_767);

pub type Subscriber = Arc<dyn Fn(Message) + Send + Sync>;

type Waiter = (u16, u32, mpsc::Sender<Message>);

struct Inner {
    stream: Mutex<TcpStream>,
    local_key: String,
    version: Mutex<[u8; 3]>,
    nonces: Mutex<Nonces>,
    connected: AtomicBool,
    waiters: Mutex<Vec<Waiter>>,
    subscriber: Subscriber,
    /// How long the link may go without one decoded frame before it is
    /// treated as dead. Pings are answered every 10 seconds.
    liveness: Duration,
}

pub struct LocalChannel {
    inner: Arc<Inner>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalError(pub String);

impl std::fmt::Display for LocalError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl LocalChannel {
    /// Connect to `host`, negotiate the protocol version, and start the reader.
    pub fn connect(
        host: &str,
        local_key: &str,
        subscriber: Subscriber,
    ) -> Result<Self, LocalError> {
        Self::connect_addr(&format!("{host}:{PORT}"), local_key, subscriber)
    }

    pub fn connect_addr(
        addr: &str,
        local_key: &str,
        subscriber: Subscriber,
    ) -> Result<Self, LocalError> {
        Self::connect_with_liveness(addr, local_key, subscriber, PING_INTERVAL * 6)
    }

    fn connect_with_liveness(
        addr: &str,
        local_key: &str,
        subscriber: Subscriber,
        liveness: Duration,
    ) -> Result<Self, LocalError> {
        let sock: SocketAddr = addr
            .parse()
            .map_err(|_| LocalError(format!("Failed to connect to {addr}: not an IP address")))?;
        let stream = TcpStream::connect_timeout(&sock, TIMEOUT)
            .map_err(|e| LocalError(format!("Failed to connect to {addr}: {e}")))?;
        stream.set_nodelay(true).ok();
        let reader = stream
            .try_clone()
            .map_err(|e| LocalError(format!("Failed to connect to {addr}: {e}")))?;
        let inner = Arc::new(Inner {
            stream: Mutex::new(stream),
            local_key: local_key.to_string(),
            version: Mutex::new(protocol::V1),
            nonces: Mutex::new(Nonces {
                connect_nonce: CONNECT_NONCE.next(),
                ack_nonce: None,
            }),
            connected: AtomicBool::new(true),
            waiters: Mutex::new(Vec::new()),
            subscriber,
            liveness,
        });
        let reader_inner = inner.clone();
        thread::Builder::new()
            .name("roborock-local".into())
            .spawn(move || read_loop(reader, reader_inner))
            .map_err(|e| LocalError(format!("cannot start the local reader: {e}")))?;
        let channel = Self { inner };
        if let Err(e) = channel.hello() {
            channel.close();
            return Err(e);
        }
        let pinger = Arc::downgrade(&channel.inner);
        thread::Builder::new()
            .name("roborock-local-ping".into())
            .spawn(move || loop {
                thread::sleep(PING_INTERVAL);
                let Some(inner) = pinger.upgrade() else {
                    return;
                };
                if !inner.connected.load(Ordering::SeqCst) {
                    return;
                }
                let ch = LocalChannel { inner };
                let ping = Message {
                    version: ch.version(),
                    ..Message::new(protocol::PING_REQUEST, None)
                };
                // A failed ping is only logged in Python too; the reader notices a dead socket.
                let _ = ch.exchange(ping, protocol::PING_RESPONSE);
            })
            .ok();
        Ok(channel)
    }

    fn hello(&self) -> Result<(), LocalError> {
        for version in [protocol::V1, protocol::L01] {
            let connect_nonce = self.nonces().connect_nonce;
            let hello = Message {
                version,
                seq: 1,
                random: connect_nonce,
                ..Message::new(protocol::HELLO_REQUEST, None)
            };
            *self.inner.version.lock().unwrap_or_else(|e| e.into_inner()) = version;
            if let Ok(reply) = self.exchange(hello, protocol::HELLO_RESPONSE) {
                self.inner
                    .nonces
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .ack_nonce = Some(reply.random);
                return Ok(());
            }
            if !self.is_connected() {
                break;
            }
        }
        Err(LocalError(
            "Failed to connect to device with any known protocol".into(),
        ))
    }

    pub fn version(&self) -> [u8; 3] {
        *self.inner.version.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn nonces(&self) -> Nonces {
        *self.inner.nonces.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn is_connected(&self) -> bool {
        self.inner.connected.load(Ordering::SeqCst)
    }

    pub fn publish(&self, msg: &Message) -> Result<(), LocalError> {
        if !self.is_connected() {
            return Err(LocalError("Not connected to device".into()));
        }
        let wire = protocol::encode(msg, &self.inner.local_key, true, Some(self.nonces()))
            .map_err(|e| LocalError(format!("Failed to encode message: {e}")))?;
        let mut stream = self.inner.stream.lock().unwrap_or_else(|e| e.into_inner());
        stream.write_all(&wire).map_err(|e| {
            self.inner.connected.store(false, Ordering::SeqCst);
            LocalError(format!("Failed to send message: {e}"))
        })
    }

    /// Send `msg` and wait for the frame with the same seq and `response_protocol`.
    fn exchange(&self, msg: Message, response_protocol: u16) -> Result<Message, LocalError> {
        let (tx, rx) = mpsc::channel();
        self.inner
            .waiters
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push((response_protocol, msg.seq, tx));
        let result = self.publish(&msg).and_then(|_| {
            rx.recv_timeout(TIMEOUT)
                .map_err(|_| LocalError(format!("Command timed out after {}s", TIMEOUT.as_secs())))
        });
        self.inner
            .waiters
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .retain(|(p, s, _)| !(*p == response_protocol && *s == msg.seq));
        result
    }

    pub fn close(&self) {
        self.inner.connected.store(false, Ordering::SeqCst);
        let stream = self.inner.stream.lock().unwrap_or_else(|e| e.into_inner());
        let _ = stream.shutdown(Shutdown::Both);
    }
}

/// Marks the link down when the reader stops, however it stops (a panic in
/// a subscriber included), so callers fall back to MQTT and the link is
/// reconnected instead of looking alive forever.
struct ReaderGuard(Arc<Inner>);

impl Drop for ReaderGuard {
    fn drop(&mut self) {
        self.0.connected.store(false, Ordering::SeqCst);
        if let Ok(stream) = self.0.stream.lock() {
            let _ = stream.shutdown(Shutdown::Both);
        }
        // Wake anyone waiting on a reply that will now never come.
        self.0
            .waiters
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clear();
    }
}

fn read_loop(mut reader: TcpStream, inner: Arc<Inner>) {
    let _guard = ReaderGuard(inner.clone());
    let mut frames = FrameBuffer::default();
    let mut chunk = [0u8; 8192];
    reader
        .set_read_timeout(Some(Duration::from_millis(500)))
        .ok();
    // Liveness counts decoded frames, not bytes: a framer stuck waiting on
    // a bogus length still receives bytes but never a message.
    let mut last_frame = Instant::now();
    while inner.connected.load(Ordering::SeqCst) {
        if last_frame.elapsed() > inner.liveness {
            break;
        }
        match reader.read(&mut chunk) {
            Ok(0) => break,
            Ok(n) => frames.push(&chunk[..n]),
            Err(e)
                if matches!(
                    e.kind(),
                    ErrorKind::WouldBlock | ErrorKind::TimedOut | ErrorKind::Interrupted
                ) =>
            {
                continue;
            }
            Err(_) => break,
        }
        while let Some(frame) = frames.next_frame() {
            let nonces = *inner.nonces.lock().unwrap_or_else(|e| e.into_inner());
            let Ok(msg) = protocol::decode_frame(&frame, &inner.local_key, Some(nonces)) else {
                continue;
            };
            last_frame = Instant::now();
            let waiter = {
                let mut waiters = inner.waiters.lock().unwrap_or_else(|e| e.into_inner());
                waiters
                    .iter()
                    .position(|(p, s, _)| *p == msg.protocol && *s == msg.seq)
                    .map(|i| waiters.remove(i))
            };
            match waiter {
                Some((_, _, tx)) => {
                    let _ = tx.send(msg);
                }
                None => (inner.subscriber)(msg),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;

    const KEY: &str = "0123456789abcdef";

    /// A fake vacuum that answers hello in "1.0", then echoes one RPC.
    fn fake_device(answer_hello: bool) -> (String, thread::JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap().to_string();
        let handle = thread::spawn(move || {
            let (mut sock, _) = listener.accept().unwrap();
            sock.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
            let mut frames = FrameBuffer::default();
            let mut chunk = [0u8; 4096];
            loop {
                let n = match sock.read(&mut chunk) {
                    Ok(0) | Err(_) => return,
                    Ok(n) => n,
                };
                frames.push(&chunk[..n]);
                while let Some(frame) = frames.next_frame() {
                    let msg = protocol::decode_frame(&frame, KEY, None).unwrap();
                    let reply = match msg.protocol {
                        protocol::HELLO_REQUEST if answer_hello => Message {
                            seq: msg.seq,
                            random: 4242,
                            ..Message::new(protocol::HELLO_RESPONSE, None)
                        },
                        protocol::GENERAL_REQUEST => {
                            let doc: serde_json::Value =
                                serde_json::from_slice(msg.payload.as_ref().unwrap()).unwrap();
                            let inner: serde_json::Value =
                                serde_json::from_str(doc["dps"]["101"].as_str().unwrap()).unwrap();
                            let point = serde_json::json!({"id": inner["id"], "result": ["ok"]});
                            let body = serde_json::json!({"dps": {"102": point.to_string()}});
                            Message::new(
                                protocol::GENERAL_RESPONSE,
                                Some(body.to_string().into_bytes()),
                            )
                        }
                        _ => continue,
                    };
                    let wire = protocol::encode(&reply, KEY, true, None).unwrap();
                    sock.write_all(&wire).unwrap();
                }
            }
        });
        (addr, handle)
    }

    #[test]
    fn hello_negotiates_v1_and_records_the_ack_nonce() {
        let (addr, _h) = fake_device(true);
        let got = Arc::new(Mutex::new(Vec::<Message>::new()));
        let sink = got.clone();
        let ch =
            LocalChannel::connect_addr(&addr, KEY, Arc::new(move |m| sink.lock().unwrap().push(m)))
                .unwrap();
        assert_eq!(ch.version(), protocol::V1);
        assert_eq!(ch.nonces().ack_nonce, Some(4242));
        let req = protocol::Request::new("get_status", None);
        ch.publish(&req.to_message(protocol::GENERAL_REQUEST, ch.version(), None))
            .unwrap();
        let deadline = Instant::now() + Duration::from_secs(5);
        while got.lock().unwrap().is_empty() && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(10));
        }
        let msgs = got.lock().unwrap();
        let resp = protocol::decode_rpc_response(&msgs[0]).unwrap();
        assert_eq!(resp.id, Some(req.id as u64));
        ch.close();
    }

    #[test]
    fn a_device_that_never_says_hello_is_refused() {
        let (addr, _h) = fake_device(false);
        let err = LocalChannel::connect_addr(&addr, KEY, Arc::new(|_| {}))
            .err()
            .unwrap();
        assert!(err.0.contains("any known protocol"), "{err}");
    }

    /// A fake vacuum that answers hello, then runs `then` on the socket.
    fn scripted_device(then: impl FnOnce(&mut TcpStream) + Send + 'static) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap().to_string();
        thread::spawn(move || {
            let (mut sock, _) = listener.accept().unwrap();
            sock.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
            let mut frames = FrameBuffer::default();
            let mut chunk = [0u8; 4096];
            loop {
                let n = match sock.read(&mut chunk) {
                    Ok(0) | Err(_) => return,
                    Ok(n) => n,
                };
                frames.push(&chunk[..n]);
                if let Some(frame) = frames.next_frame() {
                    let msg = protocol::decode_frame(&frame, KEY, None).unwrap();
                    let reply = Message {
                        seq: msg.seq,
                        random: 4242,
                        ..Message::new(protocol::HELLO_RESPONSE, None)
                    };
                    sock.write_all(&protocol::encode(&reply, KEY, true, None).unwrap())
                        .unwrap();
                    break;
                }
            }
            then(&mut sock);
            // Hold the socket open so only the reader's own state can end the link.
            thread::sleep(Duration::from_secs(10));
        });
        addr
    }

    fn becomes_disconnected(ch: &LocalChannel, within: Duration) -> bool {
        let deadline = Instant::now() + within;
        while Instant::now() < deadline {
            if !ch.is_connected() {
                return true;
            }
            thread::sleep(Duration::from_millis(20));
        }
        false
    }

    #[test]
    fn a_reader_that_dies_marks_the_link_down() {
        let addr = scripted_device(|sock| {
            thread::sleep(Duration::from_millis(200));
            let push = Message::new(
                protocol::GENERAL_RESPONSE,
                Some(br#"{"dps":{"121":5}}"#.to_vec()),
            );
            sock.write_all(&protocol::encode(&push, KEY, true, None).unwrap())
                .unwrap();
        });
        // A subscriber that panics takes the reader thread down with it.
        let ch =
            LocalChannel::connect_addr(&addr, KEY, Arc::new(|_| panic!("subscriber bug"))).unwrap();
        assert!(ch.is_connected());
        assert!(
            becomes_disconnected(&ch, Duration::from_secs(3)),
            "the link still looks alive"
        );
    }

    #[test]
    fn a_framer_stuck_on_a_bogus_length_resets_the_link() {
        let addr = scripted_device(|sock| {
            // A plausible prefix for a frame that never completes, then a
            // trickle of bytes: data keeps arriving, messages never do.
            let _ = sock.write_all(&100_000u32.to_be_bytes());
            for _ in 0..60 {
                if sock.write_all(b"x").is_err() {
                    return;
                }
                thread::sleep(Duration::from_millis(50));
            }
        });
        let ch = LocalChannel::connect_with_liveness(
            &addr,
            KEY,
            Arc::new(|_| {}),
            Duration::from_secs(1),
        )
        .unwrap();
        assert!(
            becomes_disconnected(&ch, Duration::from_secs(4)),
            "a stalled framer kept the link up"
        );
    }
}
