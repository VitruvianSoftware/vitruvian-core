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
/// Numbers every channel, so a late signal from an old one can be told
/// apart from the current one.
static GENERATION: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

pub type Subscriber = Arc<dyn Fn(Message) + Send + Sync>;
/// Called once when the link goes down, so a caller can fail its own
/// requests that were sent over it.
pub type DownHook = Arc<dyn Fn() + Send + Sync>;

type Waiter = (u16, u32, mpsc::Sender<Message>);
/// Bytes for the writer thread, and where to report how the write went.
type WriteJob = (Vec<u8>, mpsc::Sender<std::io::Result<()>>);

struct Inner {
    /// Only for shutting the socket down: writes go through `writer`.
    stream: Mutex<TcpStream>,
    /// The writer thread's queue; None once the link is down.
    writer: Mutex<Option<mpsc::Sender<WriteJob>>>,
    local_key: String,
    version: Mutex<[u8; 3]>,
    nonces: Mutex<Nonces>,
    connected: AtomicBool,
    waiters: Mutex<Vec<Waiter>>,
    subscriber: Subscriber,
    /// How long the link may go without one decoded frame before it is
    /// treated as dead. Pings are answered every 10 seconds.
    liveness: Duration,
    on_down: Mutex<Option<DownHook>>,
    generation: u64,
}

impl Inner {
    /// Mark the link down, once: fail every waiter and call the hook. Never
    /// waits on the socket, so a stuck send can't hold it up.
    fn mark_down(&self) {
        self.connected.store(false, Ordering::SeqCst);
        // No more writes; the writer thread ends after the one in hand.
        self.writer.lock().unwrap_or_else(|e| e.into_inner()).take();
        // Dropping the senders wakes every exchange at once.
        self.waiters
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clear();
        let hook = self
            .on_down
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take();
        if let Some(hook) = hook {
            hook();
        }
    }
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
        let writer_stream = stream
            .try_clone()
            .map_err(|e| LocalError(format!("Failed to connect to {addr}: {e}")))?;
        let (writer_tx, writer_rx) = mpsc::channel::<WriteJob>();
        let inner = Arc::new(Inner {
            stream: Mutex::new(stream),
            writer: Mutex::new(Some(writer_tx)),
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
            on_down: Mutex::new(None),
            generation: GENERATION.fetch_add(1, Ordering::SeqCst),
        });
        thread::Builder::new()
            .name("roborock-local-write".into())
            .spawn(move || write_loop(writer_stream, writer_rx))
            .map_err(|e| LocalError(format!("cannot start the local writer: {e}")))?;
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

    /// Run `hook` once when this link goes down (straight away if it already
    /// has).
    pub fn set_on_down(&self, hook: DownHook) {
        *self.inner.on_down.lock().unwrap_or_else(|e| e.into_inner()) = Some(hook);
        if !self.is_connected() {
            self.inner.mark_down();
        }
    }

    pub fn version(&self) -> [u8; 3] {
        *self.inner.version.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn nonces(&self) -> Nonces {
        *self.inner.nonces.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// This channel's number, unique in the process.
    pub fn generation(&self) -> u64 {
        self.inner.generation
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
        // A hard deadline for the caller, whatever the kernel does with one
        // write(): the writer thread does the blocking, and if it isn't done
        // in time the socket is shut down under it.
        let deadline = Instant::now() + TIMEOUT;
        let writer = self
            .inner
            .writer
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
            .ok_or_else(|| LocalError("Not connected to device".into()))?;
        let (done_tx, done_rx) = mpsc::channel();
        if writer.send((wire, done_tx)).is_err() {
            self.inner.mark_down();
            return Err(LocalError(
                "Failed to send message: the writer has stopped".into(),
            ));
        }
        let outcome = match done_rx.recv_timeout(deadline.saturating_duration_since(Instant::now()))
        {
            Ok(Ok(())) => return Ok(()),
            Ok(Err(e)) => format!("Failed to send message: {e}"),
            Err(_) => "Failed to send message: the device stopped reading".to_string(),
        };
        // The link can't be trusted now: part of the frame may be on the wire.
        // The whole frame may also still arrive, if the writer hands its last
        // bytes to the kernel just after the deadline; the shutdown below
        // doesn't take back bytes the kernel already holds. The caller then
        // re-sends the command over MQTT, so the vacuum can get it twice.
        // That is acceptable for every command we send: reads are harmless,
        // start/pause/stop/dock, wash start/stop and the resumes set the same
        // state again, `find_me` beeps twice, and `app_segment_clean`
        // restarts the same room run. It is no worse than a command that runs
        // but whose reply is lost.
        self.inner.mark_down();
        if let Ok(stream) = self.inner.stream.lock() {
            let _ = stream.shutdown(Shutdown::Both);
        }
        Err(LocalError(outcome))
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
            rx.recv_timeout(TIMEOUT).map_err(|e| match e {
                mpsc::RecvTimeoutError::Timeout => {
                    LocalError(format!("Command timed out after {}s", TIMEOUT.as_secs()))
                }
                mpsc::RecvTimeoutError::Disconnected => {
                    LocalError("The local connection to the vacuum was lost".into())
                }
            })
        });
        self.inner
            .waiters
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .retain(|(p, s, _)| !(*p == response_protocol && *s == msg.seq));
        result
    }

    pub fn close(&self) {
        self.inner.mark_down();
        let stream = self.inner.stream.lock().unwrap_or_else(|e| e.into_inner());
        let _ = stream.shutdown(Shutdown::Both);
    }
}

/// Writes each job with the socket's write timeout; the caller enforces the
/// overall deadline (macOS can stretch one write() past its timeout while a
/// peer drains slowly). Ends at the first failure, or when the link is
/// marked down.
fn write_loop(mut stream: TcpStream, jobs: mpsc::Receiver<WriteJob>) {
    stream.set_write_timeout(Some(TIMEOUT)).ok();
    while let Ok((data, done)) = jobs.recv() {
        let result = stream.write_all(&data);
        let failed = result.is_err();
        let _ = done.send(result);
        if failed {
            return;
        }
    }
}

/// Marks the link down when the reader stops, however it stops (a panic in
/// a subscriber included), so callers fall back to MQTT and the link is
/// reconnected instead of looking alive forever.
struct ReaderGuard(Arc<Inner>);

impl Drop for ReaderGuard {
    fn drop(&mut self) {
        // Waiters and the hook first, before touching the socket. Sends no
        // longer hold the socket lock (the writer thread owns its own handle),
        // but nothing here should depend on that.
        self.0.mark_down();
        if let Ok(stream) = self.0.stream.lock() {
            let _ = stream.shutdown(Shutdown::Both);
        }
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
            thread::sleep(Duration::from_secs(30));
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
        let downs = Arc::new(Mutex::new(0usize));
        let d = downs.clone();
        ch.set_on_down(Arc::new(move || *d.lock().unwrap() += 1));
        assert!(ch.is_connected());
        assert!(
            becomes_disconnected(&ch, Duration::from_secs(3)),
            "the link still looks alive"
        );
        // The owner hears about it exactly once.
        thread::sleep(Duration::from_millis(50));
        assert_eq!(*downs.lock().unwrap(), 1);
    }

    #[test]
    fn a_request_in_flight_fails_at_once_when_the_reader_dies() {
        // The device takes a ping, never answers it, and pushes a message
        // that kills the reader.
        let addr = scripted_device(|sock| {
            let mut frames = FrameBuffer::default();
            let mut chunk = [0u8; 4096];
            loop {
                let n = match sock.read(&mut chunk) {
                    Ok(0) | Err(_) => return,
                    Ok(n) => n,
                };
                frames.push(&chunk[..n]);
                if frames.next_frame().is_some() {
                    break;
                }
            }
            let push = Message::new(
                protocol::GENERAL_RESPONSE,
                Some(br#"{"dps":{"121":5}}"#.to_vec()),
            );
            sock.write_all(&protocol::encode(&push, KEY, true, None).unwrap())
                .unwrap();
        });
        let ch =
            LocalChannel::connect_addr(&addr, KEY, Arc::new(|_| panic!("subscriber bug"))).unwrap();
        let started = Instant::now();
        let ping = Message {
            version: ch.version(),
            ..Message::new(protocol::PING_REQUEST, None)
        };
        let err = ch.exchange(ping, protocol::PING_RESPONSE).unwrap_err();
        assert!(
            started.elapsed() < Duration::from_secs(3),
            "waited {:?}",
            started.elapsed()
        );
        assert!(err.0.contains("connection to the vacuum was lost"), "{err}");
    }

    /// Sends 60 KB frames until one fails, checking that every send comes
    /// back within the deadline plus `slack`. Returns whether one failed.
    fn every_send_is_bounded(
        ch: Arc<LocalChannel>,
        slack: Duration,
        for_at_most: Duration,
    ) -> bool {
        let (tx, rx) = mpsc::channel();
        thread::spawn(move || {
            let big = Message::new(protocol::GENERAL_REQUEST, Some(vec![b'x'; 60_000]));
            loop {
                let started = Instant::now();
                let failed = ch.publish(&big).is_err();
                if tx.send((failed, started.elapsed())).is_err() || failed {
                    return;
                }
            }
        });
        let started = Instant::now();
        while started.elapsed() < for_at_most {
            match rx.recv_timeout(TIMEOUT + slack + Duration::from_secs(2)) {
                Ok((failed, took)) => {
                    assert!(took <= TIMEOUT + slack, "one send took {took:?}");
                    if failed {
                        return true;
                    }
                }
                Err(_) => panic!("a send blocked past its deadline"),
            }
        }
        false
    }

    #[test]
    fn a_device_that_stops_reading_cannot_block_a_send_forever() {
        // The device answers hello and then never reads again.
        let addr = scripted_device(|_| {});
        let ch = Arc::new(LocalChannel::connect_addr(&addr, KEY, Arc::new(|_| {})).unwrap());
        let failed =
            every_send_is_bounded(ch.clone(), Duration::from_secs(1), Duration::from_secs(14));
        assert!(failed, "the buffers never filled");
        // A send that timed out may have left part of a frame on the wire: the link is down.
        assert!(!ch.is_connected());
    }

    #[test]
    fn a_slowly_draining_device_cannot_stretch_one_send_past_its_deadline() {
        // The device reads a trickle: enough that writes make progress, never
        // enough to keep up.
        let addr = scripted_device(|sock| {
            let mut buf = [0u8; 512];
            for _ in 0..60 {
                if sock.read(&mut buf).is_err() {
                    return;
                }
                thread::sleep(Duration::from_millis(500));
            }
        });
        let ch = Arc::new(LocalChannel::connect_addr(&addr, KEY, Arc::new(|_| {})).unwrap());
        let failed =
            every_send_is_bounded(ch.clone(), Duration::from_secs(1), Duration::from_secs(14));
        assert!(failed, "no send ever hit its deadline");
        assert!(!ch.is_connected());
    }

    #[test]
    fn the_down_hook_fires_once_however_the_link_goes_down() {
        let addr = scripted_device(|sock| {
            thread::sleep(Duration::from_millis(200));
            // Also end the reader, after close() has run.
            let _ = sock.shutdown(Shutdown::Both);
        });
        let ch = LocalChannel::connect_addr(&addr, KEY, Arc::new(|_| {})).unwrap();
        let downs = Arc::new(Mutex::new(0usize));
        let d = downs.clone();
        ch.set_on_down(Arc::new(move || *d.lock().unwrap() += 1));
        ch.close();
        ch.close();
        thread::sleep(Duration::from_millis(600));
        assert_eq!(*downs.lock().unwrap(), 1);
    }

    #[test]
    fn a_hook_set_on_a_link_already_down_fires_at_once() {
        let addr = scripted_device(|_| {});
        let ch = LocalChannel::connect_addr(&addr, KEY, Arc::new(|_| {})).unwrap();
        ch.close();
        let downs = Arc::new(Mutex::new(0usize));
        let d = downs.clone();
        ch.set_on_down(Arc::new(move || *d.lock().unwrap() += 1));
        assert_eq!(*downs.lock().unwrap(), 1);
    }

    #[test]
    fn requests_fail_before_cleanup_waits_on_the_socket() {
        // Cleanup shuts the socket down, which means taking its lock. Sends
        // no longer hold that lock (the writer thread has its own handle), so
        // a real stuck send can't block it; this test holds the lock itself,
        // for the whole of cleanup, which is the worst a holder could do.
        // Requests must still fail at once.
        let (kill_tx, kill_rx) = mpsc::channel::<()>();
        let addr = scripted_device(move |sock| {
            let _ = kill_rx.recv_timeout(Duration::from_secs(10));
            let push = Message::new(
                protocol::GENERAL_RESPONSE,
                Some(br#"{"dps":{"121":5}}"#.to_vec()),
            );
            sock.write_all(&protocol::encode(&push, KEY, true, None).unwrap())
                .unwrap();
        });
        // A subscriber that panics takes the reader down when the push lands.
        let ch = Arc::new(
            LocalChannel::connect_addr(&addr, KEY, Arc::new(|_| panic!("subscriber bug"))).unwrap(),
        );
        let fired = Arc::new(Mutex::new(false));
        let f = fired.clone();
        ch.set_on_down(Arc::new(move || *f.lock().unwrap() = true));
        // A request of the channel's own, waiting on a reply that never comes.
        let (ping_tx, ping_rx) = mpsc::channel();
        let pinger = ch.clone();
        thread::spawn(move || {
            let ping = Message {
                version: pinger.version(),
                ..Message::new(protocol::PING_REQUEST, None)
            };
            let _ = ping_tx.send(pinger.exchange(ping, protocol::PING_RESPONSE));
        });
        thread::sleep(Duration::from_millis(200));

        let held = ch.inner.stream.lock().unwrap();
        kill_tx.send(()).unwrap();
        let ping = ping_rx.recv_timeout(Duration::from_secs(3));
        let hook_fired = *fired.lock().unwrap();
        drop(held);

        let err = ping
            .expect("the request waited behind the socket lock")
            .unwrap_err();
        assert!(err.0.contains("connection to the vacuum was lost"), "{err}");
        assert!(hook_fired, "the down hook waited behind the socket lock");
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
