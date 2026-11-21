// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! Shared by the tests that run against a real Postgres (rules_itest starts
//! it; `:postgres` in this folder's BUILD): finding it, making a database of
//! one's own in it, and a small TCP proxy to cut and restore the road to it.

#![allow(dead_code)]

use std::sync::{Arc, Mutex};

use tokio::net::{TcpListener, TcpStream};
use tokio::task::AbortHandle;

const POSTGRES_LABEL: &str = "@@//apps/suites/vitruvian-relay/relay:postgres";

/// The loopback port rules_itest gave the Postgres service.
pub fn postgres_port() -> u16 {
    let ports =
        std::env::var("ASSIGNED_PORTS").expect("ASSIGNED_PORTS: not running under rules_itest");
    let map: serde_json::Value = serde_json::from_str(&ports).expect("ASSIGNED_PORTS is not JSON");
    map.get(POSTGRES_LABEL)
        .and_then(|v| {
            v.as_u64()
                .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
        })
        .unwrap_or_else(|| panic!("no port for {POSTGRES_LABEL} in {ports}")) as u16
}

/// A new, empty database in the itest Postgres, so a test never sees another's
/// rows. The URL to reach it at `port` (the service's, or a proxy's); plain
/// TCP (`sslmode=disable`), as the itest Postgres has no certificate.
pub async fn fresh_database() -> Database {
    let port = postgres_port();
    let (client, connection) = tokio_postgres::connect(
        &format!("host=127.0.0.1 port={port} user=postgres dbname=postgres"),
        tokio_postgres::NoTls,
    )
    .await
    .expect("connect to the itest Postgres");
    tokio::spawn(connection);
    let name = format!("t_{}", vitruvian_relay::random_id());
    client
        .batch_execute(&format!("CREATE DATABASE {name}"))
        .await
        .expect("create a database");
    Database { name }
}

pub struct Database {
    name: String,
}

impl Database {
    /// How to reach this database through `port`.
    pub fn url_at(&self, port: u16) -> String {
        format!(
            "postgresql://postgres@127.0.0.1:{port}/{}?sslmode=disable",
            self.name
        )
    }

    /// How to reach it directly.
    pub fn url(&self) -> String {
        self.url_at(postgres_port())
    }

    /// A plain connection, for looking at the tables the way a person
    /// running psql would.
    pub async fn client(&self) -> tokio_postgres::Client {
        let (client, connection) = tokio_postgres::connect(
            &format!(
                "host=127.0.0.1 port={} user=postgres dbname={}",
                postgres_port(),
                self.name
            ),
            tokio_postgres::NoTls,
        )
        .await
        .expect("connect to the test database");
        tokio::spawn(connection);
        client
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode {
    /// Passes connections through to Postgres.
    Open,
    /// The database is gone: every connection is dropped as it arrives, and
    /// the ones open are cut.
    Down,
    /// The road is there but nothing comes back: connections are accepted and
    /// held in silence (the open ones are cut).
    Silent,
    /// Everything works, but each answer from Postgres reaches the client this
    /// much late. Connections already open stay open.
    Slow(std::time::Duration),
}

struct Shared {
    mode: Mode,
    /// How late answers are (zero unless the mode is `Slow`).
    delay: std::time::Duration,
    /// The tasks carrying (or holding) connections.
    open: Vec<AbortHandle>,
}

/// A TCP proxy between the store and Postgres. `set(Mode::Down)` is "the
/// database stopped"; `set(Mode::Open)` is "it is back".
pub struct Proxy {
    pub port: u16,
    shared: Arc<Mutex<Shared>>,
}

impl Proxy {
    pub async fn start(upstream_port: u16) -> Proxy {
        let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind proxy");
        let port = listener.local_addr().unwrap().port();
        let shared = Arc::new(Mutex::new(Shared {
            mode: Mode::Open,
            delay: std::time::Duration::ZERO,
            open: Vec::new(),
        }));
        let accept_shared = shared.clone();
        tokio::spawn(async move {
            loop {
                let Ok((client, _)) = listener.accept().await else {
                    continue;
                };
                let mut sh = accept_shared.lock().unwrap();
                let task = match sh.mode {
                    Mode::Down => continue, // `client` drops: closed at once
                    Mode::Silent => tokio::spawn(async move {
                        let _held = client;
                        std::future::pending::<()>().await;
                    }),
                    Mode::Open | Mode::Slow(_) => {
                        let shared = accept_shared.clone();
                        tokio::spawn(async move {
                            let Ok(upstream) =
                                TcpStream::connect(("127.0.0.1", upstream_port)).await
                            else {
                                return;
                            };
                            let (mut client_r, mut client_w) = tokio::io::split(client);
                            let (mut up_r, mut up_w) = tokio::io::split(upstream);
                            // Client to Postgres: straight through. Postgres to
                            // client: held back by the current delay.
                            let to_pg = tokio::io::copy(&mut client_r, &mut up_w);
                            let to_client = async {
                                use tokio::io::{AsyncReadExt, AsyncWriteExt};
                                let mut buf = [0u8; 8192];
                                loop {
                                    let n = match up_r.read(&mut buf).await {
                                        Ok(0) | Err(_) => break,
                                        Ok(n) => n,
                                    };
                                    let delay = shared.lock().unwrap().delay;
                                    if !delay.is_zero() {
                                        tokio::time::sleep(delay).await;
                                    }
                                    if client_w.write_all(&buf[..n]).await.is_err() {
                                        break;
                                    }
                                }
                            };
                            tokio::select! {
                                _ = to_pg => {}
                                _ = to_client => {}
                            }
                        })
                    }
                };
                sh.open.retain(|h| !h.is_finished());
                sh.open.push(task.abort_handle());
            }
        });
        Proxy { port, shared }
    }

    pub fn set(&self, mode: Mode) {
        let mut sh = self.shared.lock().unwrap();
        sh.mode = mode;
        sh.delay = match mode {
            Mode::Slow(d) => d,
            _ => std::time::Duration::ZERO,
        };
        // A database that went away takes its connections with it. Open and
        // slow keep what is open (a slow link is the same connections, later).
        if matches!(mode, Mode::Down | Mode::Silent) {
            for h in sh.open.drain(..) {
                h.abort();
            }
        }
    }
}
