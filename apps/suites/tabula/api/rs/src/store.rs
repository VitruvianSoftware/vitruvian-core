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

use crate::crypto::{epoch_ms_to_iso8601, now_epoch_ms, now_iso8601, uuid_v4};
use crate::migration_guard::SchemaColumnProbe;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::sync::{mpsc, Arc, Mutex};
use std::time::Duration;

// ============================================================================
// 1. Redis Store Trait + InMemoryRedis + RESP2 TCP Client
// ============================================================================

pub trait RedisStore: Send + Sync {
    fn get(&self, key: &str) -> Result<Option<String>, String>;
    fn set(&self, key: &str, value: &str) -> Result<(), String>;
    fn set_ex(&self, key: &str, value: &str, ttl_secs: u64) -> Result<(), String>;
    fn del(&self, keys: &[&str]) -> Result<usize, String>;
    fn eval_version_check(&self, key: &str, client_version: u64) -> Result<(i64, u64), String>;
    fn sadd(&self, key: &str, member: &str) -> Result<usize, String>;
    fn scard(&self, key: &str) -> Result<usize, String>;
    fn expire(&self, key: &str, ttl_secs: u64) -> Result<bool, String>;
    fn hset(&self, key: &str, fields: &[(&str, &str)]) -> Result<usize, String>;
    fn hgetall(&self, key: &str) -> Result<BTreeMap<String, String>, String>;
    fn zadd(&self, key: &str, score: f64, member: &str) -> Result<usize, String>;
    fn zcard(&self, key: &str) -> Result<usize, String>;
    fn zrangebyscore(&self, key: &str, min_score: f64) -> Result<Vec<String>, String>;
    fn publish(&self, channel: &str, message: &str) -> Result<usize, String>;
    fn subscribe(&self, channel: &str) -> Result<RedisSubscription, String>;
}

pub struct RedisSubscription {
    pub receiver: mpsc::Receiver<String>,
    on_close: Option<Box<dyn FnOnce() + Send>>,
}

impl RedisSubscription {
    pub fn new(receiver: mpsc::Receiver<String>, on_close: impl FnOnce() + Send + 'static) -> Self {
        Self {
            receiver,
            on_close: Some(Box::new(on_close)),
        }
    }

    pub fn close(&mut self) {
        if let Some(cb) = self.on_close.take() {
            cb();
        }
    }
}

impl Drop for RedisSubscription {
    fn drop(&mut self) {
        self.close();
    }
}

#[derive(Debug, Clone)]
pub struct StringEntry {
    pub value: String,
    pub ttl_secs: Option<u64>,
}

#[derive(Default)]
struct InMemoryRedisInner {
    fail_error: Option<String>,
    eval_override: Option<(i64, u64)>,
    strings: HashMap<String, StringEntry>,
    sets: HashMap<String, HashSet<String>>,
    hashes: HashMap<String, BTreeMap<String, String>>,
    zsets: HashMap<String, Vec<(f64, String)>>,
    expirations: HashMap<String, u64>,
    subscribers: HashMap<String, Vec<mpsc::Sender<String>>>,
    pub published: Vec<(String, String)>,
    pub eval_calls: Vec<(String, u64)>,
    pub set_calls: Vec<(String, String, Option<u64>)>,
    pub del_calls: Vec<Vec<String>>,
    pub unsubscribe_count: usize,
    pub quit_count: usize,
}

#[derive(Clone, Default)]
pub struct InMemoryRedis {
    inner: Arc<Mutex<InMemoryRedisInner>>,
}

impl InMemoryRedis {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn set_fail_error(&self, err: Option<&str>) {
        let mut g = self.inner.lock().unwrap();
        g.fail_error = err.map(|s| s.to_string());
    }

    pub fn set_eval_override(&self, ov: Option<(i64, u64)>) {
        let mut g = self.inner.lock().unwrap();
        g.eval_override = ov;
    }

    pub fn eval_calls(&self) -> Vec<(String, u64)> {
        self.inner.lock().unwrap().eval_calls.clone()
    }

    pub fn set_calls(&self) -> Vec<(String, String, Option<u64>)> {
        self.inner.lock().unwrap().set_calls.clone()
    }

    pub fn del_calls(&self) -> Vec<Vec<String>> {
        self.inner.lock().unwrap().del_calls.clone()
    }

    pub fn published_messages(&self) -> Vec<(String, String)> {
        self.inner.lock().unwrap().published.clone()
    }

    pub fn unsubscribe_count(&self) -> usize {
        self.inner.lock().unwrap().unsubscribe_count
    }

    pub fn quit_count(&self) -> usize {
        self.inner.lock().unwrap().quit_count
    }

    pub fn clear_all(&self) {
        let mut g = self.inner.lock().unwrap();
        *g = InMemoryRedisInner::default();
    }
}

impl RedisStore for InMemoryRedis {
    fn get(&self, key: &str) -> Result<Option<String>, String> {
        let g = self.inner.lock().unwrap();
        if let Some(err) = &g.fail_error {
            return Err(err.clone());
        }
        Ok(g.strings.get(key).map(|e| e.value.clone()))
    }

    fn set(&self, key: &str, value: &str) -> Result<(), String> {
        let mut g = self.inner.lock().unwrap();
        if let Some(err) = &g.fail_error {
            return Err(err.clone());
        }
        g.set_calls.push((key.to_string(), value.to_string(), None));
        g.strings.insert(
            key.to_string(),
            StringEntry {
                value: value.to_string(),
                ttl_secs: None,
            },
        );
        Ok(())
    }

    fn set_ex(&self, key: &str, value: &str, ttl_secs: u64) -> Result<(), String> {
        let mut g = self.inner.lock().unwrap();
        if let Some(err) = &g.fail_error {
            return Err(err.clone());
        }
        g.set_calls
            .push((key.to_string(), value.to_string(), Some(ttl_secs)));
        g.strings.insert(
            key.to_string(),
            StringEntry {
                value: value.to_string(),
                ttl_secs: Some(ttl_secs),
            },
        );
        g.expirations.insert(key.to_string(), ttl_secs);
        Ok(())
    }

    fn del(&self, keys: &[&str]) -> Result<usize, String> {
        let mut g = self.inner.lock().unwrap();
        if let Some(err) = &g.fail_error {
            return Err(err.clone());
        }
        g.del_calls
            .push(keys.iter().map(|s| (*s).to_string()).collect());
        let mut removed = 0;
        for &k in keys {
            if g.strings.remove(k).is_some() {
                removed += 1;
            }
            if g.sets.remove(k).is_some() {
                removed += 1;
            }
            if g.hashes.remove(k).is_some() {
                removed += 1;
            }
            if g.zsets.remove(k).is_some() {
                removed += 1;
            }
        }
        Ok(removed)
    }

    fn eval_version_check(&self, key: &str, client_version: u64) -> Result<(i64, u64), String> {
        let mut g = self.inner.lock().unwrap();
        if let Some(err) = &g.fail_error {
            return Err(err.clone());
        }
        g.eval_calls.push((key.to_string(), client_version));
        if let Some(ov) = g.eval_override {
            return Ok(ov);
        }
        let current = g
            .strings
            .get(key)
            .and_then(|e| e.value.parse::<u64>().ok())
            .unwrap_or(0);
        if client_version < current {
            Ok((0, current))
        } else {
            let next = current + 1;
            g.strings.insert(
                key.to_string(),
                StringEntry {
                    value: next.to_string(),
                    ttl_secs: None,
                },
            );
            Ok((1, next))
        }
    }

    fn sadd(&self, key: &str, member: &str) -> Result<usize, String> {
        let mut g = self.inner.lock().unwrap();
        if let Some(err) = &g.fail_error {
            return Err(err.clone());
        }
        let set = g.sets.entry(key.to_string()).or_default();
        Ok(usize::from(set.insert(member.to_string())))
    }

    fn scard(&self, key: &str) -> Result<usize, String> {
        let g = self.inner.lock().unwrap();
        if let Some(err) = &g.fail_error {
            return Err(err.clone());
        }
        Ok(g.sets.get(key).map(|s| s.len()).unwrap_or(0))
    }

    fn expire(&self, key: &str, ttl_secs: u64) -> Result<bool, String> {
        let mut g = self.inner.lock().unwrap();
        if let Some(err) = &g.fail_error {
            return Err(err.clone());
        }
        g.expirations.insert(key.to_string(), ttl_secs);
        Ok(true)
    }

    fn hset(&self, key: &str, fields: &[(&str, &str)]) -> Result<usize, String> {
        let mut g = self.inner.lock().unwrap();
        if let Some(err) = &g.fail_error {
            return Err(err.clone());
        }
        let map = g.hashes.entry(key.to_string()).or_default();
        for &(k, v) in fields {
            map.insert(k.to_string(), v.to_string());
        }
        Ok(fields.len())
    }

    fn hgetall(&self, key: &str) -> Result<BTreeMap<String, String>, String> {
        let g = self.inner.lock().unwrap();
        if let Some(err) = &g.fail_error {
            return Err(err.clone());
        }
        Ok(g.hashes.get(key).cloned().unwrap_or_default())
    }

    fn zadd(&self, key: &str, score: f64, member: &str) -> Result<usize, String> {
        let mut g = self.inner.lock().unwrap();
        if let Some(err) = &g.fail_error {
            return Err(err.clone());
        }
        let zset = g.zsets.entry(key.to_string()).or_default();
        zset.push((score, member.to_string()));
        zset.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
        Ok(1)
    }

    fn zcard(&self, key: &str) -> Result<usize, String> {
        let g = self.inner.lock().unwrap();
        if let Some(err) = &g.fail_error {
            return Err(err.clone());
        }
        Ok(g.zsets.get(key).map(|z| z.len()).unwrap_or(0))
    }

    fn zrangebyscore(&self, key: &str, min_score: f64) -> Result<Vec<String>, String> {
        let g = self.inner.lock().unwrap();
        if let Some(err) = &g.fail_error {
            return Err(err.clone());
        }
        let Some(zset) = g.zsets.get(key) else {
            return Ok(Vec::new());
        };
        Ok(zset
            .iter()
            .filter(|(score, _)| *score >= min_score)
            .map(|(_, m)| m.clone())
            .collect())
    }

    fn publish(&self, channel: &str, message: &str) -> Result<usize, String> {
        let mut g = self.inner.lock().unwrap();
        if let Some(err) = &g.fail_error {
            return Err(err.clone());
        }
        g.published.push((channel.to_string(), message.to_string()));
        let mut delivered = 0;
        if let Some(subs) = g.subscribers.get_mut(channel) {
            subs.retain(|tx| {
                if tx.send(message.to_string()).is_ok() {
                    delivered += 1;
                    true
                } else {
                    false
                }
            });
        }
        Ok(delivered)
    }

    fn subscribe(&self, channel: &str) -> Result<RedisSubscription, String> {
        let (tx, rx) = mpsc::channel();
        {
            let mut g = self.inner.lock().unwrap();
            if let Some(err) = &g.fail_error {
                return Err(err.clone());
            }
            g.subscribers
                .entry(channel.to_string())
                .or_default()
                .push(tx);
        }
        let inner_clone = Arc::clone(&self.inner);
        Ok(RedisSubscription::new(rx, move || {
            if let Ok(mut g) = inner_clone.lock() {
                g.unsubscribe_count += 1;
                g.quit_count += 1;
            }
        }))
    }
}

// ============================================================================
// 2. Pure-Rust PostgreSQL v3 Wire Protocol Client (`PgClient`)
// ============================================================================

#[derive(Debug, Clone)]
pub struct PgConfig {
    pub host: String,
    pub port: u16,
    pub user: String,
    pub password: Option<String>,
    pub database: String,
}

impl PgConfig {
    pub fn parse_url(url: &str) -> Result<Self, String> {
        let rest = url
            .strip_prefix("postgresql://")
            .or_else(|| url.strip_prefix("postgres://"))
            .ok_or_else(|| "Invalid DATABASE_URL scheme".to_string())?;
        let (authority, path_and_query) = match rest.split_once('/') {
            Some((a, p)) => (a, p),
            None => (rest, "postgres"),
        };
        let database = path_and_query
            .split('?')
            .next()
            .filter(|s| !s.is_empty())
            .unwrap_or("postgres")
            .to_string();

        let (userinfo, hostport) = match authority.rsplit_once('@') {
            Some((u, hp)) => (Some(u), hp),
            None => (None, authority),
        };
        let (user, password) = match userinfo {
            Some(u) => match u.split_once(':') {
                Some((usr, pwd)) => (usr.to_string(), Some(pwd.to_string())),
                None => (u.to_string(), None),
            },
            None => ("postgres".to_string(), None),
        };
        let (host, port) = match hostport.rsplit_once(':') {
            Some((h, p)) => (
                h.to_string(),
                p.parse::<u16>().map_err(|_| "Invalid Postgres port")?,
            ),
            None => (hostport.to_string(), 5432),
        };
        Ok(Self {
            host,
            port,
            user,
            password,
            database,
        })
    }
}

pub struct PgClient {
    config: PgConfig,
}

impl PgClient {
    pub fn from_url(url: &str) -> Result<Self, String> {
        Ok(Self {
            config: PgConfig::parse_url(url)?,
        })
    }

    fn connect_stream(&self) -> Result<TcpStream, String> {
        let addr_str = format!("{}:{}", self.config.host, self.config.port);
        let addr: SocketAddr = addr_str
            .to_socket_addrs()
            .map_err(|e| format!("Failed to resolve {addr_str}: {e}"))?
            .next()
            .ok_or_else(|| format!("No socket address for {addr_str}"))?;
        let mut stream = TcpStream::connect_timeout(&addr, Duration::from_secs(5))
            .map_err(|e| format!("Failed to connect to Postgres at {addr}: {e}"))?;
        let _ = stream.set_read_timeout(Some(Duration::from_secs(10)));
        let _ = stream.set_write_timeout(Some(Duration::from_secs(10)));

        // Build v3.0 StartupMessage
        let mut payload = Vec::new();
        payload.extend_from_slice(&196_608i32.to_be_bytes()); // protocol 3.0
        payload.extend_from_slice(b"user\0");
        payload.extend_from_slice(self.config.user.as_bytes());
        payload.push(0);
        payload.extend_from_slice(b"database\0");
        payload.extend_from_slice(self.config.database.as_bytes());
        payload.push(0);
        payload.extend_from_slice(b"client_encoding\0UTF8\0\0");

        let total_len = (payload.len() + 4) as i32;
        stream
            .write_all(&total_len.to_be_bytes())
            .map_err(|e| e.to_string())?;
        stream.write_all(&payload).map_err(|e| e.to_string())?;
        stream.flush().map_err(|e| e.to_string())?;

        // Read until ReadyForQuery ('Z')
        loop {
            let (tag, body) = Self::read_message(&mut stream)?;
            match tag {
                b'R' => {
                    if body.len() < 4 {
                        return Err("Truncated Postgres Authentication message".to_string());
                    }
                    let auth_code = i32::from_be_bytes([body[0], body[1], body[2], body[3]]);
                    match auth_code {
                        0 => {} // AuthenticationOk
                        3 => {
                            // CleartextPassword
                            let pwd = self.config.password.as_deref().unwrap_or("");
                            let len = (4 + pwd.len() + 1) as i32;
                            stream.write_all(&[b'p']).map_err(|e| e.to_string())?;
                            stream
                                .write_all(&len.to_be_bytes())
                                .map_err(|e| e.to_string())?;
                            stream
                                .write_all(pwd.as_bytes())
                                .map_err(|e| e.to_string())?;
                            stream.write_all(&[0]).map_err(|e| e.to_string())?;
                            stream.flush().map_err(|e| e.to_string())?;
                        }
                        other => {
                            return Err(format!("Unsupported Postgres auth method {other}"));
                        }
                    }
                }
                b'Z' => break,
                b'E' => return Err(Self::parse_error_response(&body)),
                _ => {}
            }
        }
        Ok(stream)
    }

    fn read_message(stream: &mut TcpStream) -> Result<(u8, Vec<u8>), String> {
        let mut hdr = [0u8; 5];
        stream
            .read_exact(&mut hdr)
            .map_err(|e| format!("Postgres read error: {e}"))?;
        let tag = hdr[0];
        let len = i32::from_be_bytes([hdr[1], hdr[2], hdr[3], hdr[4]]);
        if len < 4 {
            return Err(format!("Invalid Postgres message length {len}"));
        }
        let mut body = vec![0u8; (len - 4) as usize];
        if !body.is_empty() {
            stream
                .read_exact(&mut body)
                .map_err(|e| format!("Postgres body read error: {e}"))?;
        }
        Ok((tag, body))
    }

    fn parse_error_response(body: &[u8]) -> String {
        let mut idx = 0;
        let mut code = String::new();
        let mut msg = String::new();
        while idx < body.len() {
            let field_type = body[idx];
            idx += 1;
            if field_type == 0 {
                break;
            }
            let end = body[idx..]
                .iter()
                .position(|&b| b == 0)
                .map(|p| idx + p)
                .unwrap_or(body.len());
            let val = String::from_utf8_lossy(&body[idx..end]).to_string();
            idx = (end + 1).min(body.len());
            if field_type == b'C' {
                code = val;
            } else if field_type == b'M' {
                msg = val;
            }
        }
        if code.is_empty() {
            msg
        } else {
            format!("{code}: {msg}")
        }
    }

    pub fn query_simple(&self, sql: &str) -> Result<Vec<BTreeMap<String, Option<String>>>, String> {
        let mut stream = self.connect_stream()?;
        let len = (4 + sql.len() + 1) as i32;
        stream.write_all(&[b'Q']).map_err(|e| e.to_string())?;
        stream
            .write_all(&len.to_be_bytes())
            .map_err(|e| e.to_string())?;
        stream
            .write_all(sql.as_bytes())
            .map_err(|e| e.to_string())?;
        stream.write_all(&[0]).map_err(|e| e.to_string())?;
        stream.flush().map_err(|e| e.to_string())?;

        let mut col_names: Vec<String> = Vec::new();
        let mut rows: Vec<BTreeMap<String, Option<String>>> = Vec::new();
        let mut query_err: Option<String> = None;

        loop {
            let (tag, body) = Self::read_message(&mut stream)?;
            match tag {
                b'T' => {
                    col_names.clear();
                    if body.len() >= 2 {
                        let num_fields = i16::from_be_bytes([body[0], body[1]]) as usize;
                        let mut pos = 2;
                        for _ in 0..num_fields {
                            let Some(nul) = body[pos..].iter().position(|&b| b == 0) else {
                                break;
                            };
                            let name = String::from_utf8_lossy(&body[pos..pos + nul]).to_string();
                            col_names.push(name);
                            pos += nul + 1 + 18;
                        }
                    }
                }
                b'D' => {
                    if body.len() >= 2 {
                        let num_cols = i16::from_be_bytes([body[0], body[1]]) as usize;
                        let mut pos = 2;
                        let mut row = BTreeMap::new();
                        for col_idx in 0..num_cols {
                            if pos + 4 > body.len() {
                                break;
                            }
                            let col_len = i32::from_be_bytes([
                                body[pos],
                                body[pos + 1],
                                body[pos + 2],
                                body[pos + 3],
                            ]);
                            pos += 4;
                            let col_name = col_names
                                .get(col_idx)
                                .cloned()
                                .unwrap_or_else(|| format!("col_{col_idx}"));
                            if col_len < 0 {
                                row.insert(col_name, None);
                            } else {
                                let clen = col_len as usize;
                                if pos + clen <= body.len() {
                                    let val =
                                        String::from_utf8_lossy(&body[pos..pos + clen]).to_string();
                                    row.insert(col_name, Some(val));
                                    pos += clen;
                                }
                            }
                        }
                        rows.push(row);
                    }
                }
                b'E' => {
                    query_err = Some(Self::parse_error_response(&body));
                }
                b'Z' => break,
                _ => {}
            }
        }

        let _ = stream.write_all(&[b'X', 0, 0, 0, 4]);
        if let Some(err) = query_err {
            return Err(err);
        }
        Ok(rows)
    }

    pub fn execute_simple(&self, sql: &str) -> Result<(), String> {
        let _ = self.query_simple(sql)?;
        Ok(())
    }
}

impl SchemaColumnProbe for PgClient {
    fn query_present_columns(&self) -> Result<Vec<(String, String)>, String> {
        let rows = self.query_simple(
            "SELECT table_name::text AS table_name, column_name::text AS column_name \
             FROM information_schema.columns WHERE table_schema = 'public'",
        )?;
        let mut out = Vec::with_capacity(rows.len());
        for r in rows {
            if let (Some(Some(t)), Some(Some(c))) = (r.get("table_name"), r.get("column_name")) {
                out.push((t.clone(), c.clone()));
            }
        }
        Ok(out)
    }
}

// ============================================================================
// 3. Domain Records & DataStore
// ============================================================================

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserRecord {
    pub id: String,
    pub email: String,
    #[serde(skip_serializing)]
    pub password_hash: Option<String>,
    pub name: Option<String>,
    pub tier: String,
    pub created_at: String,
    pub updated_at: String,
    pub last_login_at: Option<String>,
    pub preferences: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TabRecord {
    pub id: String,
    pub workspace_id: String,
    pub url: String,
    pub title: Option<String>,
    pub favicon_url: Option<String>,
    pub position: i64,
    pub is_pinned: bool,
    pub created_at: String,
    pub updated_at: String,
    pub last_accessed_at: String,
    pub metadata: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResourceRecord {
    pub id: String,
    pub workspace_id: String,
    pub section_id: Option<String>,
    pub title: String,
    pub url: String,
    pub favicon_url: Option<String>,
    pub position: i64,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SectionRecord {
    pub id: String,
    pub workspace_id: String,
    pub title: String,
    pub position: i64,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteRecord {
    pub id: String,
    pub workspace_id: String,
    pub title: String,
    pub content: String,
    pub position: i64,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskRecord {
    pub id: String,
    pub workspace_id: String,
    pub title: String,
    pub completed: bool,
    pub due_date: Option<String>,
    pub position: i64,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceRecord {
    pub id: String,
    pub user_id: String,
    pub group_id: Option<String>,
    pub name: String,
    pub description: Option<String>,
    pub color: Option<String>,
    pub icon: Option<String>,
    pub position: i64,
    pub version: u64,
    pub active_device_id: Option<String>,
    pub active_device_seen_at: Option<String>,
    #[serde(skip)]
    pub active_device_seen_at_ms: Option<i64>,
    pub created_at: String,
    pub updated_at: String,
    pub settings: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpaceGroupRecord {
    pub id: String,
    pub user_id: String,
    pub title: String,
    pub color: Option<String>,
    pub collapsed: bool,
    pub position: i64,
    pub version: u64,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackupRecord {
    pub id: String,
    pub user_id: String,
    pub workspace_id: Option<String>,
    pub name: Option<String>,
    #[serde(rename = "type")]
    pub backup_type: String,
    pub snapshot: Value,
    pub size_bytes: usize,
    pub created_at: String,
    #[serde(skip)]
    pub created_at_ms: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionRecord {
    pub id: String,
    pub user_id: String,
    pub refresh_token_hash: String,
    pub device_info: Value,
    pub ip_address: Option<String>,
    pub user_agent: Option<String>,
    pub expires_at: String,
    #[serde(skip)]
    pub expires_at_ms: i64,
    pub created_at: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpaceCollaboratorRecord {
    pub id: String,
    pub workspace_id: String,
    pub user_id: Option<String>,
    pub invitee_email: String,
    pub role: String,
    pub status: String,
    pub invited_by_user_id: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ShareLinkRecord {
    pub id: String,
    pub workspace_id: String,
    pub token_hash: String,
    pub relay_id_hash: Option<String>,
    pub role: String,
    pub label: Option<String>,
    pub created_by_user_id: String,
    pub expires_at: Option<String>,
    #[serde(skip)]
    pub expires_at_ms: Option<i64>,
    pub revoked_at: Option<String>,
    pub created_at: String,
}

#[derive(Default)]
pub struct DataStoreInner {
    pub schema_drift_code: Option<String>,
    pub internal_error: Option<String>,
    pub users: BTreeMap<String, UserRecord>,
    pub workspaces: BTreeMap<String, WorkspaceRecord>,
    pub tabs: BTreeMap<String, TabRecord>,
    pub sections: BTreeMap<String, SectionRecord>,
    pub resources: BTreeMap<String, ResourceRecord>,
    pub notes: BTreeMap<String, NoteRecord>,
    pub tasks: BTreeMap<String, TaskRecord>,
    pub space_groups: BTreeMap<String, SpaceGroupRecord>,
    pub backups: BTreeMap<String, BackupRecord>,
    pub sessions: BTreeMap<String, SessionRecord>,
    pub collaborators: BTreeMap<String, SpaceCollaboratorRecord>,
    pub share_links: BTreeMap<String, ShareLinkRecord>,
}

#[derive(Clone, Default)]
pub struct DataStore {
    pub inner: Arc<Mutex<DataStoreInner>>,
}

impl DataStore {
    pub fn new() -> Self {
        let store = Self::default();
        store.seed_default_e2e_users();
        store
    }

    pub fn seed_default_e2e_users(&self) {
        let now = now_iso8601();
        let mut g = self.inner.lock().unwrap();
        for spec in crate::ALL_SEED_USERS {
            g.users
                .entry(spec.id.to_string())
                .or_insert_with(|| UserRecord {
                    id: spec.id.to_string(),
                    email: spec.email.to_string(),
                    password_hash: None,
                    name: Some(spec.name.to_string()),
                    tier: spec.tier.to_string(),
                    created_at: now.clone(),
                    updated_at: now.clone(),
                    last_login_at: Some(now.clone()),
                    preferences: json!({}),
                });
        }
    }

    pub fn load_users_from_pg(&self, pg: &PgClient) {
        if let Ok(rows) = pg.query_simple("SELECT id, email, name, tier FROM users") {
            let now = now_iso8601();
            let mut g = self.inner.lock().unwrap();
            for row in rows {
                let Some(Some(id)) = row.get("id") else {
                    continue;
                };
                let Some(Some(email)) = row.get("email") else {
                    continue;
                };
                let name = row.get("name").and_then(|v| v.clone());
                let tier = row
                    .get("tier")
                    .and_then(|v| v.clone())
                    .unwrap_or_else(|| "free".to_string());
                g.users.insert(
                    id.clone(),
                    UserRecord {
                        id: id.clone(),
                        email: email.clone(),
                        password_hash: None,
                        name,
                        tier,
                        created_at: now.clone(),
                        updated_at: now.clone(),
                        last_login_at: Some(now.clone()),
                        preferences: json!({}),
                    },
                );
            }
        }
    }

    pub fn clear_all(&self) {
        let mut g = self.inner.lock().unwrap();
        *g = DataStoreInner::default();
    }

    pub fn set_schema_drift(&self, code: Option<&str>) {
        let mut g = self.inner.lock().unwrap();
        g.schema_drift_code = code.map(|s| s.to_string());
    }

    pub fn set_internal_error(&self, msg: Option<&str>) {
        let mut g = self.inner.lock().unwrap();
        g.internal_error = msg.map(|s| s.to_string());
    }

    pub fn check_injected_error(&self) -> Result<(), crate::errors::AppError> {
        let g = self.inner.lock().unwrap();
        if let Some(code) = &g.schema_drift_code {
            return Err(crate::errors::AppError::SchemaDrift {
                code: code.clone(),
                message:
                    "Invalid `prisma.model.findMany()` invocation: column does not exist in current database."
                        .to_string(),
            });
        }
        if let Some(msg) = &g.internal_error {
            return Err(crate::errors::AppError::Internal {
                message: msg.clone(),
            });
        }
        Ok(())
    }

    pub fn put_user(&self, user: UserRecord) {
        let mut g = self.inner.lock().unwrap();
        g.users.insert(user.id.clone(), user);
    }

    pub fn upsert_user_by_email(&self, email: &str, name: &str) -> UserRecord {
        let mut g = self.inner.lock().unwrap();
        let now = now_iso8601();
        if let Some(existing) = g.users.values_mut().find(|u| u.email == email) {
            existing.last_login_at = Some(now.clone());
            existing.updated_at = now;
            return existing.clone();
        }
        let id = uuid_v4();
        let rec = UserRecord {
            id: id.clone(),
            email: email.to_string(),
            password_hash: None,
            name: Some(name.to_string()),
            tier: "free".to_string(),
            created_at: now.clone(),
            updated_at: now.clone(),
            last_login_at: Some(now),
            preferences: json!({}),
        };
        g.users.insert(id, rec.clone());
        rec
    }

    /// Assemble a full workspace JSON value including sorted `tabs`, `sections` (with nested `resources`),
    /// `notes`, `tasks`, and `resources` matching Prisma's `WORKSPACE_INCLUDE`.
    pub fn hydrate_workspace_json(g: &DataStoreInner, ws: &WorkspaceRecord) -> Value {
        let mut tabs: Vec<&TabRecord> = g
            .tabs
            .values()
            .filter(|t| t.workspace_id == ws.id)
            .collect();
        tabs.sort_by_key(|t| t.position);

        let mut sections: Vec<&SectionRecord> = g
            .sections
            .values()
            .filter(|s| s.workspace_id == ws.id)
            .collect();
        sections.sort_by_key(|s| s.position);

        let mut all_resources: Vec<&ResourceRecord> = g
            .resources
            .values()
            .filter(|r| r.workspace_id == ws.id)
            .collect();
        all_resources.sort_by_key(|r| r.position);

        let sections_json: Vec<Value> = sections
            .into_iter()
            .map(|sec| {
                let sec_resources: Vec<&ResourceRecord> = all_resources
                    .iter()
                    .copied()
                    .filter(|r| r.section_id.as_deref() == Some(sec.id.as_str()))
                    .collect();
                json!({
                    "id": sec.id,
                    "workspaceId": sec.workspace_id,
                    "title": sec.title,
                    "position": sec.position,
                    "createdAt": sec.created_at,
                    "updatedAt": sec.updated_at,
                    "resources": sec_resources,
                })
            })
            .collect();

        let mut notes: Vec<&NoteRecord> = g
            .notes
            .values()
            .filter(|n| n.workspace_id == ws.id)
            .collect();
        notes.sort_by_key(|n| n.position);

        let mut tasks: Vec<&TaskRecord> = g
            .tasks
            .values()
            .filter(|t| t.workspace_id == ws.id)
            .collect();
        tasks.sort_by_key(|t| t.position);

        let mut val = serde_json::to_value(ws).unwrap_or_else(|_| json!({}));
        if let Some(obj) = val.as_object_mut() {
            obj.insert("tabs".to_string(), json!(tabs));
            obj.insert("sections".to_string(), Value::Array(sections_json));
            obj.insert("notes".to_string(), json!(notes));
            obj.insert("tasks".to_string(), json!(tasks));
            obj.insert("resources".to_string(), json!(all_resources));
        }
        val
    }
}

// ============================================================================
// 4. RESP2 TCP Redis Client (`RespRedisStore`) with InMemory Fallback
// ============================================================================

pub struct RespRedisStore {
    addr: Option<SocketAddr>,
    fallback: InMemoryRedis,
}

impl RespRedisStore {
    pub fn from_url_or_memory(url: Option<&str>) -> Self {
        let addr = url.and_then(|u| {
            let rest = u.strip_prefix("redis://").unwrap_or(u);
            let hostport = rest.split('/').next().unwrap_or(rest);
            let hostport = hostport.rsplit('@').next().unwrap_or(hostport);
            hostport.to_socket_addrs().ok()?.next()
        });
        Self {
            addr,
            fallback: InMemoryRedis::new(),
        }
    }

    fn send_command(&self, args: &[&str]) -> Option<RespValue> {
        let addr = self.addr?;
        let mut stream = TcpStream::connect_timeout(&addr, Duration::from_millis(1500)).ok()?;
        let _ = stream.set_read_timeout(Some(Duration::from_millis(2000)));
        let _ = stream.set_write_timeout(Some(Duration::from_millis(2000)));

        let mut buf = format!("*{}\r\n", args.len()).into_bytes();
        for a in args {
            buf.extend_from_slice(format!("${}\r\n", a.len()).as_bytes());
            buf.extend_from_slice(a.as_bytes());
            buf.extend_from_slice(b"\r\n");
        }
        stream.write_all(&buf).ok()?;
        stream.flush().ok()?;

        let mut reader = BufReader::new(stream);
        Self::read_resp(&mut reader)
    }

    fn read_resp<R: BufRead>(reader: &mut R) -> Option<RespValue> {
        let mut line = String::new();
        if reader.read_line(&mut line).ok()? == 0 {
            return None;
        }
        let trimmed = line.trim_end_matches(&['\r', '\n'][..]);
        let prefix = trimmed.as_bytes().first().copied()?;
        let payload = &trimmed[1..];
        match prefix {
            b'+' => Some(RespValue::Simple(payload.to_string())),
            b'-' => Some(RespValue::Error(payload.to_string())),
            b':' => Some(RespValue::Int(payload.parse().ok()?)),
            b'$' => {
                let len: isize = payload.parse().ok()?;
                if len < 0 {
                    return Some(RespValue::Nil);
                }
                let mut bytes = vec![0u8; len as usize];
                reader.read_exact(&mut bytes).ok()?;
                let mut crlf = [0u8; 2];
                let _ = reader.read_exact(&mut crlf);
                Some(RespValue::Bulk(String::from_utf8_lossy(&bytes).to_string()))
            }
            b'*' => {
                let count: isize = payload.parse().ok()?;
                if count < 0 {
                    return Some(RespValue::Nil);
                }
                let mut items = Vec::with_capacity(count as usize);
                for _ in 0..count {
                    items.push(Self::read_resp(reader)?);
                }
                Some(RespValue::Array(items))
            }
            _ => None,
        }
    }
}

#[derive(Debug, Clone)]
enum RespValue {
    Simple(String),
    Error(String),
    Int(i64),
    Bulk(String),
    Array(Vec<RespValue>),
    Nil,
}

impl RedisStore for RespRedisStore {
    fn get(&self, key: &str) -> Result<Option<String>, String> {
        if let Some(resp) = self.send_command(&["GET", key]) {
            match resp {
                RespValue::Bulk(s) | RespValue::Simple(s) => return Ok(Some(s)),
                RespValue::Nil => return Ok(None),
                RespValue::Error(e) => return Err(e),
                _ => {}
            }
        }
        self.fallback.get(key)
    }

    fn set(&self, key: &str, value: &str) -> Result<(), String> {
        let _ = self.send_command(&["SET", key, value]);
        self.fallback.set(key, value)
    }

    fn set_ex(&self, key: &str, value: &str, ttl_secs: u64) -> Result<(), String> {
        let ttl_str = ttl_secs.to_string();
        let _ = self.send_command(&["SET", key, value, "EX", &ttl_str]);
        self.fallback.set_ex(key, value, ttl_secs)
    }

    fn del(&self, keys: &[&str]) -> Result<usize, String> {
        let mut cmd = Vec::with_capacity(keys.len() + 1);
        cmd.push("DEL");
        cmd.extend_from_slice(keys);
        let _ = self.send_command(&cmd);
        self.fallback.del(keys)
    }

    fn eval_version_check(&self, key: &str, client_version: u64) -> Result<(i64, u64), String> {
        let script = "local current = tonumber(redis.call('GET', KEYS[1]) or '0')\nif tonumber(ARGV[1]) < current then\n  return {0, current}\nend\nlocal next = current + 1\nredis.call('SET', KEYS[1], tostring(next))\nreturn {1, next}";
        let cv = client_version.to_string();
        if let Some(RespValue::Array(items)) = self.send_command(&["EVAL", script, "1", key, &cv]) {
            if items.len() == 2 {
                if let (RespValue::Int(ok), RespValue::Int(ver)) = (&items[0], &items[1]) {
                    return Ok((*ok, *ver as u64));
                }
            }
        }
        self.fallback.eval_version_check(key, client_version)
    }

    fn sadd(&self, key: &str, member: &str) -> Result<usize, String> {
        let _ = self.send_command(&["SADD", key, member]);
        self.fallback.sadd(key, member)
    }

    fn scard(&self, key: &str) -> Result<usize, String> {
        if let Some(RespValue::Int(n)) = self.send_command(&["SCARD", key]) {
            return Ok(n.max(0) as usize);
        }
        self.fallback.scard(key)
    }

    fn expire(&self, key: &str, ttl_secs: u64) -> Result<bool, String> {
        let ttl_str = ttl_secs.to_string();
        let _ = self.send_command(&["EXPIRE", key, &ttl_str]);
        self.fallback.expire(key, ttl_secs)
    }

    fn hset(&self, key: &str, fields: &[(&str, &str)]) -> Result<usize, String> {
        let mut cmd = Vec::with_capacity(2 + fields.len() * 2);
        cmd.push("HSET");
        cmd.push(key);
        for &(k, v) in fields {
            cmd.push(k);
            cmd.push(v);
        }
        let _ = self.send_command(&cmd);
        self.fallback.hset(key, fields)
    }

    fn hgetall(&self, key: &str) -> Result<BTreeMap<String, String>, String> {
        if let Some(RespValue::Array(items)) = self.send_command(&["HGETALL", key]) {
            let mut map = BTreeMap::new();
            let mut iter = items.into_iter();
            while let (Some(RespValue::Bulk(k)), Some(RespValue::Bulk(v))) =
                (iter.next(), iter.next())
            {
                map.insert(k, v);
            }
            if !map.is_empty() {
                return Ok(map);
            }
        }
        self.fallback.hgetall(key)
    }

    fn zadd(&self, key: &str, score: f64, member: &str) -> Result<usize, String> {
        let sc = score.to_string();
        let _ = self.send_command(&["ZADD", key, &sc, member]);
        self.fallback.zadd(key, score, member)
    }

    fn zcard(&self, key: &str) -> Result<usize, String> {
        if let Some(RespValue::Int(n)) = self.send_command(&["ZCARD", key]) {
            return Ok(n.max(0) as usize);
        }
        self.fallback.zcard(key)
    }

    fn zrangebyscore(&self, key: &str, min_score: f64) -> Result<Vec<String>, String> {
        let min_s = min_score.to_string();
        if let Some(RespValue::Array(items)) =
            self.send_command(&["ZRANGEBYSCORE", key, &min_s, "+inf"])
        {
            let mut out = Vec::new();
            for item in items {
                if let RespValue::Bulk(s) = item {
                    out.push(s);
                }
            }
            if !out.is_empty() {
                return Ok(out);
            }
        }
        self.fallback.zrangebyscore(key, min_score)
    }

    fn publish(&self, channel: &str, message: &str) -> Result<usize, String> {
        let _ = self.send_command(&["PUBLISH", channel, message]);
        self.fallback.publish(channel, message)
    }

    fn subscribe(&self, channel: &str) -> Result<RedisSubscription, String> {
        self.fallback.subscribe(channel)
    }
}

pub fn format_epoch_ms(ms: i64) -> String {
    epoch_ms_to_iso8601(ms)
}

pub fn current_ms() -> i64 {
    now_epoch_ms()
}
