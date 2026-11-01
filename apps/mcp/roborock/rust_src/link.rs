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

//! The live connection to one V1 vacuum: cloud discovery, MQTT, the local
//! TCP channel, and V1 RPC over whichever of them is up.
//!
//! This is what python-roborock 7.12.1's device manager and `V1Channel` do
//! for the calls this crate makes (`devices/device_manager.py`,
//! `devices/rpc/v1_channel.py`):
//!
//! * the account's home data (devices, products, rooms) comes from the cloud
//!   once and is cached on disk, as `create_device_manager` does by default;
//! * one MQTT session to the account's broker, subscribed to the device's
//!   topic; every request over MQTT carries the security envelope;
//! * a local TCP channel when the vacuum's IP is known (asked for once over
//!   MQTT with `get_network_info`, then cached); RPCs prefer it and fall
//!   back to MQTT, and a lost local link is retried with backoff;
//! * maps (`get_map_v1`) only ever come over MQTT, encrypted with the
//!   request's nonce;
//! * unsolicited status pushes (data points 120-135) update the status.

use crate::auth::ApiError;
use crate::cloud::{self, CloudClient, UserApi};
use crate::config::{self, Credentials};
use crate::crypto;
use crate::local::LocalChannel;
use crate::mqtt;
use crate::protocol::{self, Message, Request, Rriot, SecurityData};
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

pub const RPC_TIMEOUT: Duration = Duration::from_secs(10);
const LOCAL_BACKOFF_MIN: Duration = Duration::from_secs(60);
const LOCAL_BACKOFF_MAX: Duration = Duration::from_secs(600);

/// One device from the home data, with its product.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HomeDevice {
    pub duid: String,
    pub name: String,
    pub local_key: String,
    pub pv: String,
    pub model: String,
    pub category: String,
}

impl HomeDevice {
    /// A V1 vacuum, the only kind this crate drives.
    pub fn is_v1_vacuum(&self) -> bool {
        self.pv == "1.0" && self.category == "robot.vacuum.cleaner"
    }

    /// Whether python-roborock's device manager would list it at all: V1
    /// vacuums, A01 devices and the B01 Q7/Q10 lines. Everything else is
    /// skipped as unsupported.
    pub fn is_listed(&self) -> bool {
        match self.pv.as_str() {
            "1.0" => self.category == "robot.vacuum.cleaner",
            "A01" => true,
            "B01" => {
                let part = self.model.rsplit('.').next().unwrap_or("");
                part.contains("ss") || part.contains("sc")
            }
            _ => false,
        }
    }
}

fn s(v: Option<&Value>) -> String {
    match v {
        Some(Value::String(x)) => x.clone(),
        Some(Value::Number(n)) => n.to_string(),
        _ => String::new(),
    }
}

/// `HomeData.device_products`, in the order python-roborock lists them
/// (own devices, then shared ones).
pub fn home_devices(home: &Map<String, Value>) -> Vec<HomeDevice> {
    let products: HashMap<String, &Value> = home
        .get("products")
        .and_then(Value::as_array)
        .map(|ps| ps.iter().map(|p| (s(p.get("id")), p)).collect())
        .unwrap_or_default();
    let mut out = Vec::new();
    for key in ["devices", "receivedDevices"] {
        for d in home
            .get(key)
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            let Some(product) = products.get(&s(d.get("productId"))) else {
                continue;
            };
            out.push(HomeDevice {
                duid: s(d.get("duid")),
                name: s(d.get("name")),
                local_key: s(d.get("localKey")),
                pv: s(d.get("pv")),
                model: s(product.get("model")),
                category: s(product.get("category")),
            });
        }
    }
    out
}

/// `HomeData.rooms_name_map`: iot id -> room name.
pub fn home_rooms(home: &Map<String, Value>) -> HashMap<String, String> {
    home.get("rooms")
        .and_then(Value::as_array)
        .map(|r| cloud::rooms_from(r).into_iter().collect())
        .unwrap_or_default()
}

/// The on-disk cache: home data, and per device its IP and init status.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Cache {
    pub home_data: Option<Map<String, Value>>,
    pub devices: Map<String, Value>,
}

impl Cache {
    pub fn load(path: &Path) -> Self {
        // A missing, unreadable or foreign file (the Python version kept a
        // pickle) is just an empty cache.
        let Ok(bytes) = std::fs::read(path) else {
            return Self::default();
        };
        let Ok(Value::Object(doc)) = serde_json::from_slice::<Value>(&bytes) else {
            return Self::default();
        };
        Self {
            home_data: doc.get("home_data").and_then(Value::as_object).cloned(),
            devices: doc
                .get("devices")
                .and_then(Value::as_object)
                .cloned()
                .unwrap_or_default(),
        }
    }

    pub fn save(&self, path: &Path) -> Result<(), config::ConfigError> {
        let doc = json!({
            "version": 1,
            "home_data": self.home_data,
            "devices": self.devices,
        });
        config::write_private(path, &serde_json::to_vec(&doc).unwrap_or_default())
    }

    pub fn device_value(&self, duid: &str, key: &str) -> Option<Value> {
        self.devices.get(duid)?.get(key).cloned()
    }

    pub fn set_device_value(&mut self, duid: &str, key: &str, value: Value) {
        let entry = self
            .devices
            .entry(duid.to_string())
            .or_insert_with(|| Value::Object(Map::new()));
        if let Value::Object(o) = entry {
            o.insert(key.to_string(), value);
        }
    }
}

/// Why connecting failed, and whether the stored login was the reason.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LinkError {
    pub message: String,
    pub unauthorized: bool,
}

impl LinkError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            unauthorized: false,
        }
    }
}

impl From<ApiError> for LinkError {
    fn from(e: ApiError) -> Self {
        Self {
            unauthorized: e.class_name == "RoborockInvalidCredentials",
            message: e.message,
        }
    }
}

/// Called with the status data points a device pushes on its own.
pub type PushHandler = Arc<dyn Fn(Map<String, Value>) + Send + Sync>;

type RpcWaiter = mpsc::Sender<Result<Value, String>>;
type MapWaiter = mpsc::Sender<Result<Vec<u8>, String>>;

struct Router {
    local_key: String,
    security: SecurityData,
    rpc: Mutex<HashMap<u64, RpcWaiter>>,
    maps: Mutex<HashMap<u16, MapWaiter>>,
    /// Requests sent over a local channel and not yet answered, with the
    /// generation of the channel each went out on.
    local_ids: Mutex<HashMap<u64, u64>>,
    on_push: PushHandler,
}

impl Router {
    /// Local channel `generation` went down: fail the requests sent over
    /// it now, so callers fall back to MQTT instead of waiting out their
    /// timeout. Requests on any other channel (a newer one) are left alone.
    fn local_down(&self, generation: u64) {
        let ids: Vec<u64> = {
            let mut local = self.local_ids.lock().unwrap_or_else(|e| e.into_inner());
            let ids: Vec<u64> = local
                .iter()
                .filter(|(_, g)| **g == generation)
                .map(|(id, _)| *id)
                .collect();
            for id in &ids {
                local.remove(id);
            }
            ids
        };
        let mut rpc = self.rpc.lock().unwrap_or_else(|e| e.into_inner());
        for id in ids {
            if let Some(tx) = rpc.remove(&id) {
                let _ = tx.send(Err("The local connection to the vacuum was lost".into()));
            }
        }
    }

    /// Every frame from the device, whichever way it came.
    fn dispatch(&self, msg: Message) {
        if msg.protocol == protocol::MAP_RESPONSE {
            if let Ok(Some((id, data))) = protocol::decode_map_response(&msg, &self.security) {
                if let Some(tx) = self
                    .maps
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .remove(&id)
                {
                    let _ = tx.send(Ok(data));
                }
            }
            return;
        }
        if let Some(points) = protocol::decode_dps_push(&msg) {
            (self.on_push)(points);
        }
        if let Ok(resp) = protocol::decode_rpc_response(&msg) {
            if let Some(id) = resp.id {
                if let Some(tx) = self
                    .rpc
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .remove(&id)
                {
                    let _ = tx.send(resp.result);
                }
            }
        }
    }

    fn mqtt_payload(&self, payload: &[u8]) {
        if let Ok(msg) = protocol::decode_frame(payload, &self.local_key, None) {
            self.dispatch(msg);
        }
    }
}

struct LocalState {
    channel: Option<LocalChannel>,
    next_attempt: Instant,
    backoff: Duration,
    /// A (re)connect is under way; nobody else starts one meanwhile.
    connecting: bool,
}

impl LocalState {
    fn new() -> Self {
        Self {
            channel: None,
            next_attempt: Instant::now(),
            backoff: LOCAL_BACKOFF_MIN,
            connecting: false,
        }
    }
}

/// Bring the local channel up if it is down and a retry is due. Only one
/// caller connects at a time (the poll loop and a command can both get
/// here), and a channel that is replaced is always closed, so no socket or
/// ping thread is left behind. `connect` gets whether to refresh the IP.
fn ensure_local_with(
    state: &Mutex<LocalState>,
    connect: impl FnOnce(bool) -> Result<LocalChannel, String>,
) {
    let had_channel = {
        let mut local = state.lock().unwrap_or_else(|e| e.into_inner());
        if local
            .channel
            .as_ref()
            .map(LocalChannel::is_connected)
            .unwrap_or(false)
        {
            return;
        }
        if local.connecting || Instant::now() < local.next_attempt {
            return;
        }
        local.connecting = true;
        match local.channel.take() {
            Some(dead) => {
                dead.close();
                true
            }
            None => false,
        }
    };
    // However `connect` ends (an error, or a panic), the attempt is over:
    // clear `connecting` and back off, or no caller would ever retry.
    let mut attempt = Attempt {
        state,
        finished: false,
    };
    let result = connect(had_channel);
    let mut local = state.lock().unwrap_or_else(|e| e.into_inner());
    local.connecting = false;
    match result {
        Ok(channel) => {
            if let Some(old) = local.channel.replace(channel) {
                old.close();
            }
            local.backoff = LOCAL_BACKOFF_MIN;
        }
        Err(_) => back_off(&mut local),
    }
    attempt.finished = true;
}

fn back_off(local: &mut LocalState) {
    local.next_attempt = Instant::now() + local.backoff;
    local.backoff = (local.backoff.mul_f32(1.5)).min(LOCAL_BACKOFF_MAX);
}

struct Attempt<'a> {
    state: &'a Mutex<LocalState>,
    finished: bool,
}

impl Drop for Attempt<'_> {
    fn drop(&mut self) {
        if self.finished {
            return;
        }
        let mut local = self.state.lock().unwrap_or_else(|e| e.into_inner());
        local.connecting = false;
        back_off(&mut local);
    }
}

pub struct Link {
    pub device: HomeDevice,
    pub region: String,
    mqtt: mqtt::Session,
    pub_topic: String,
    sub_topic: String,
    sub_id: u64,
    router: Arc<Router>,
    local: Mutex<LocalState>,
    /// The vacuum's local TCP port (58867; tests point it elsewhere).
    local_port: u16,
    cache: Mutex<Cache>,
    cache_path: PathBuf,
    last_map: Mutex<Option<(Vec<u8>, Vec<u8>)>>,
}

/// Inputs to `Link::open` that tests and callers may vary.
pub struct OpenOptions {
    pub cache_path: PathBuf,
    pub unauthorized: Arc<AtomicBool>,
    pub on_push: PushHandler,
    /// Picks the device from the listed ones (python-roborock's `_select`).
    pub select: Box<dyn Fn(&[HomeDevice]) -> Result<HomeDevice, String> + Send + Sync>,
}

impl Link {
    pub fn open(creds: &Credentials, opts: OpenOptions) -> Result<Self, LinkError> {
        let rriot = Rriot::from_user_data(&creds.user_data).map_err(|e| LinkError::new(e.0))?;
        let mut cache = Cache::load(&opts.cache_path);
        if cache.home_data.is_none() {
            let client = CloudClient::new(&creds.email, creds.base_url.clone());
            let api = UserApi {
                client: &client,
                user_data: &creds.user_data,
                rriot: rriot.clone(),
            };
            match api.home_data() {
                Ok(home) => cache.home_data = Some(home),
                Err(e) => {
                    let e = LinkError::from(e);
                    if e.unauthorized {
                        opts.unauthorized.store(true, Ordering::SeqCst);
                    }
                    return Err(e);
                }
            }
            let _ = cache.save(&opts.cache_path);
        }
        let home = cache.home_data.clone().unwrap_or_default();
        let listed: Vec<HomeDevice> = home_devices(&home)
            .into_iter()
            .filter(HomeDevice::is_listed)
            .collect();
        let device = (opts.select)(&listed).map_err(LinkError::new)?;

        let params = protocol::mqtt_params(&rriot).map_err(|e| LinkError::new(e.0))?;
        let flag = opts.unauthorized.clone();
        let session = mqtt::Session::connect(
            mqtt::Options {
                host: params.host,
                port: params.port,
                tls: params.tls,
                username: params.username.clone(),
                password: params.password,
                client_id: format!("rrctl-{}", crypto::hex(&crypto::random_bytes(6))),
            },
            Some(Arc::new(move || flag.store(true, Ordering::SeqCst))),
        )
        .map_err(|e| LinkError {
            unauthorized: opts.unauthorized.load(Ordering::SeqCst),
            message: e.0,
        })?;
        let router = Arc::new(Router {
            local_key: device.local_key.clone(),
            security: SecurityData::new(&rriot.k),
            rpc: Mutex::new(HashMap::new()),
            maps: Mutex::new(HashMap::new()),
            local_ids: Mutex::new(HashMap::new()),
            on_push: opts.on_push,
        });
        let sub_topic = format!("rr/m/o/{}/{}/{}", rriot.u, params.username, device.duid);
        let pub_topic = format!("rr/m/i/{}/{}/{}", rriot.u, params.username, device.duid);
        let r = router.clone();
        let sub_id = session
            .subscribe(
                &sub_topic,
                Arc::new(move |payload: &[u8]| r.mqtt_payload(payload)),
            )
            .map_err(|e| LinkError::new(e.0))?;
        let region = creds
            .user_data
            .get("region")
            .and_then(Value::as_str)
            .unwrap_or("us")
            .to_lowercase();
        let link = Self {
            device,
            region,
            mqtt: session,
            pub_topic,
            sub_topic,
            sub_id,
            router,
            local: Mutex::new(LocalState::new()),
            local_port: crate::local::PORT,
            cache: Mutex::new(cache),
            cache_path: opts.cache_path,
            last_map: Mutex::new(None),
        };
        link.ensure_local();
        Ok(link)
    }

    pub fn is_local_connected(&self) -> bool {
        self.local
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .channel
            .as_ref()
            .map(LocalChannel::is_connected)
            .unwrap_or(false)
    }

    fn save_cache(&self) {
        let cache = self.cache.lock().unwrap_or_else(|e| e.into_inner()).clone();
        let _ = cache.save(&self.cache_path);
    }

    pub fn cached(&self, key: &str) -> Option<Value> {
        self.cache
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .device_value(&self.device.duid, key)
    }

    pub fn remember(&self, key: &str, value: Value) {
        self.cache
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .set_device_value(&self.device.duid, key, value);
        self.save_cache();
    }

    pub fn home_data(&self) -> Map<String, Value> {
        self.cache
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .home_data
            .clone()
            .unwrap_or_default()
    }

    pub fn set_home_rooms(&self, rooms: &[(String, String)]) {
        let mut cache = self.cache.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(home) = cache.home_data.as_mut() {
            home.insert(
                "rooms".into(),
                Value::Array(
                    rooms
                        .iter()
                        .map(|(id, name)| json!({"id": id.parse::<i64>().map(Value::from).unwrap_or(json!(id)), "name": name}))
                        .collect(),
                ),
            );
        }
        drop(cache);
        self.save_cache();
    }

    /// Bring the local channel up if it is down and a retry is due.
    pub fn ensure_local(&self) {
        ensure_local_with(&self.local, |refresh_ip| {
            // After a drop, ask for the IP again in case DHCP moved the vacuum.
            let ip = self.network_ip(!refresh_ip)?;
            let router = self.router.clone();
            let channel = LocalChannel::connect_addr(
                &format!("{ip}:{}", self.local_port),
                &self.device.local_key,
                Arc::new(move |m| router.dispatch(m)),
            )
            .map_err(|e| e.0)?;
            let router = self.router.clone();
            let generation = channel.generation();
            channel.set_on_down(Arc::new(move || router.local_down(generation)));
            Ok(channel)
        });
    }

    /// `_get_networking_info`: the cached IP, else ask over MQTT.
    fn network_ip(&self, prefer_cache: bool) -> Result<String, String> {
        let cached = self
            .cached("network_info")
            .and_then(|v| v.get("ip").and_then(Value::as_str).map(str::to_string));
        if prefer_cache {
            if let Some(ip) = &cached {
                return Ok(ip.clone());
            }
        }
        match self.rpc_mqtt("get_network_info", None) {
            Ok(info) => {
                let ip = info
                    .get("ip")
                    .and_then(Value::as_str)
                    .map(str::to_string)
                    .ok_or_else(|| "get_network_info returned no ip".to_string())?;
                self.remember("network_info", info);
                Ok(ip)
            }
            Err(e) => cached.ok_or(e),
        }
    }

    fn wait_rpc(
        &self,
        id: u64,
        rx: mpsc::Receiver<Result<Value, String>>,
    ) -> Result<Value, String> {
        let out = rx
            .recv_timeout(RPC_TIMEOUT)
            .map_err(|_| format!("Command timed out after {}s", RPC_TIMEOUT.as_secs()))
            .and_then(|r| r);
        self.router
            .rpc
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(&id);
        out
    }

    fn rpc_mqtt(&self, method: &str, params: Option<Value>) -> Result<Value, String> {
        let req = Request::new(method, params);
        let msg = req.to_message(
            protocol::RPC_REQUEST,
            protocol::V1,
            Some(&self.router.security),
        );
        let wire = protocol::encode(&msg, &self.device.local_key, false, None).map_err(|e| e.0)?;
        let (tx, rx) = mpsc::channel();
        self.router
            .rpc
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(req.id as u64, tx);
        if let Err(e) = self.mqtt.publish(&self.pub_topic, &wire) {
            self.router
                .rpc
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .remove(&(req.id as u64));
            return Err(e.0);
        }
        self.wait_rpc(req.id as u64, rx)
    }

    fn rpc_local(&self, method: &str, params: Option<Value>) -> Option<Result<Value, String>> {
        let local = self.local.lock().unwrap_or_else(|e| e.into_inner());
        let channel = local.channel.as_ref().filter(|c| c.is_connected())?;
        let req = Request::new(method, params);
        let msg = req.to_message(protocol::GENERAL_REQUEST, channel.version(), None);
        let (tx, rx) = mpsc::channel();
        self.router
            .rpc
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(req.id as u64, tx);
        self.router
            .local_ids
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(req.id as u64, channel.generation());
        let sent = channel.publish(&msg);
        drop(local);
        let forget = || {
            self.router
                .local_ids
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .remove(&(req.id as u64));
        };
        if let Err(e) = sent {
            forget();
            self.router
                .rpc
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .remove(&(req.id as u64));
            return Some(Err(e.0));
        }
        let out = self.wait_rpc(req.id as u64, rx);
        forget();
        Some(out)
    }

    /// `RpcChannel.send_command`: local first, then MQTT. As in Python, any
    /// failure on the local channel (including the vacuum refusing) is
    /// retried over MQTT, and MQTT's answer is the one reported.
    pub fn rpc(&self, method: &str, params: Option<Value>) -> Result<Value, String> {
        self.ensure_local();
        if let Some(Ok(v)) = self.rpc_local(method, params.clone()) {
            return Ok(v);
        }
        self.rpc_mqtt(method, params)
    }

    /// `MapContentTrait.refresh`: the raw (decrypted, decompressed) map, and
    /// whether it changed since the last call.
    pub fn map(&self) -> Result<(Vec<u8>, bool), String> {
        let req = Request::new("get_map_v1", None);
        let msg = req.to_message(
            protocol::RPC_REQUEST,
            protocol::V1,
            Some(&self.router.security),
        );
        let wire = protocol::encode(&msg, &self.device.local_key, false, None).map_err(|e| e.0)?;
        let id = req.id as u16;
        let (tx, rx) = mpsc::channel();
        self.router
            .maps
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(id, tx);
        let sent = self.mqtt.publish(&self.pub_topic, &wire);
        let out = sent.map_err(|e| e.0).and_then(|_| {
            rx.recv_timeout(RPC_TIMEOUT)
                .map_err(|_| format!("Command timed out after {}s", RPC_TIMEOUT.as_secs()))
                .and_then(|r| r)
        });
        self.router
            .maps
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(&id);
        let raw = out?;
        let last = self.last_map.lock().unwrap_or_else(|e| e.into_inner());
        let changed = last.as_ref().map(|(r, _)| r != &raw).unwrap_or(true);
        Ok((raw, changed))
    }

    pub fn last_png(&self) -> Option<Vec<u8>> {
        self.last_map
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .map(|(_, png)| png.clone())
    }

    pub fn set_last_map(&self, raw: Vec<u8>, png: Vec<u8>) {
        *self.last_map.lock().unwrap_or_else(|e| e.into_inner()) = Some((raw, png));
    }

    pub fn close(&self) {
        self.mqtt.unsubscribe(&self.sub_topic, self.sub_id);
        self.mqtt.close();
        if let Some(ch) = self
            .local
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .channel
            .take()
        {
            ch.close();
        }
        self.save_cache();
    }

    /// `UserWebApiClient.get_rooms`, for room names the cached home data lacks.
    pub fn fetch_rooms(creds: &Credentials) -> Result<Vec<(String, String)>, String> {
        let rriot = Rriot::from_user_data(&creds.user_data).map_err(|e| e.0)?;
        let client = CloudClient::new(&creds.email, creds.base_url.clone());
        UserApi {
            client: &client,
            user_data: &creds.user_data,
            rriot,
        }
        .rooms()
        .map_err(|e| e.message)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn home() -> Map<String, Value> {
        json!({
            "products": [
                {"id": "p1", "model": "roborock.vacuum.a70", "category": "robot.vacuum.cleaner"},
                {"id": "p2", "model": "roborock.wm.x", "category": "roborock.wm"},
                {"id": "p3", "model": "roborock.vacuum.ss07", "category": "robot.vacuum.cleaner"}
            ],
            "devices": [
                {"duid": "d1", "name": "Rocky", "localKey": "k1", "productId": "p1", "pv": "1.0"},
                {"duid": "d2", "name": "Washer", "localKey": "k2", "productId": "p2", "pv": "1.0"},
                {"duid": "d9", "name": "Orphan", "localKey": "k9", "productId": "missing", "pv": "1.0"}
            ],
            "receivedDevices": [
                {"duid": "d3", "name": "Q10", "localKey": "k3", "productId": "p3", "pv": "B01"}
            ],
            "rooms": [{"id": 101, "name": "Kitchen"}, {"id": "102", "name": "Hall"}]
        })
        .as_object()
        .unwrap()
        .clone()
    }

    #[test]
    fn home_devices_join_products_and_skip_what_python_skips() {
        let all = home_devices(&home());
        assert_eq!(
            all.iter().map(|d| d.duid.as_str()).collect::<Vec<_>>(),
            ["d1", "d2", "d3"]
        );
        let listed: Vec<_> = all.into_iter().filter(HomeDevice::is_listed).collect();
        // A V1 washing machine is unsupported; a B01 Q10 is listed but not V1.
        assert_eq!(
            listed.iter().map(|d| d.duid.as_str()).collect::<Vec<_>>(),
            ["d1", "d3"]
        );
        assert!(listed[0].is_v1_vacuum());
        assert!(!listed[1].is_v1_vacuum());
        assert_eq!(listed[0].model, "roborock.vacuum.a70");
    }

    #[test]
    fn home_rooms_map_iot_ids_to_names() {
        let rooms = home_rooms(&home());
        assert_eq!(rooms["101"], "Kitchen");
        assert_eq!(rooms["102"], "Hall");
    }

    #[test]
    fn the_cache_round_trips_and_ignores_a_python_pickle() {
        let dir = std::env::temp_dir().join(format!(
            "rr-cache-{}-{}",
            std::process::id(),
            crypto::hex(&crypto::random_bytes(4))
        ));
        let path = dir.join("home.json");
        let mut cache = Cache {
            home_data: Some(home()),
            ..Cache::default()
        };
        cache.set_device_value("d1", "network_info", json!({"ip": "10.0.0.5"}));
        cache.save(&path).unwrap();
        let back = Cache::load(&path);
        assert_eq!(back, cache);
        assert_eq!(
            back.device_value("d1", "network_info").unwrap()["ip"],
            "10.0.0.5"
        );
        std::fs::write(&path, b"\x80\x04\x95pickle").unwrap();
        assert_eq!(Cache::load(&path), Cache::default());
        let _ = std::fs::remove_dir_all(dir);
    }

    /// A made-up device key for the round trip below.
    const KEY: &str = "0123456789abcdef";

    #[test]
    fn mqtt_frames_route_to_the_waiting_request() {
        let pushed = Arc::new(Mutex::new(Vec::new()));
        let sink = pushed.clone();
        let router = Router {
            local_key: KEY.into(),
            security: SecurityData::new("k"),
            rpc: Mutex::new(HashMap::new()),
            maps: Mutex::new(HashMap::new()),
            local_ids: Mutex::new(HashMap::new()),
            on_push: Arc::new(move |p| sink.lock().unwrap().push(p)),
        };
        let (tx, rx) = mpsc::channel();
        router.rpc.lock().unwrap().insert(321, tx);
        let point = json!({"id": 321, "result": [{"state": 8}]}).to_string();
        let reply = Message::new(
            protocol::RPC_RESPONSE,
            Some(json!({"dps": {"102": point}}).to_string().into_bytes()),
        );
        router.mqtt_payload(&protocol::encode(&reply, KEY, false, None).unwrap());
        assert_eq!(rx.try_recv().unwrap(), Ok(json!([{"state": 8}])));

        let push = Message::new(
            protocol::RPC_RESPONSE,
            Some(
                json!({"dps": {"121": 5, "122": 80}})
                    .to_string()
                    .into_bytes(),
            ),
        );
        router.mqtt_payload(&protocol::encode(&push, KEY, false, None).unwrap());
        assert_eq!(pushed.lock().unwrap()[0]["121"], 5);
    }

    #[test]
    fn local_requests_fail_at_once_when_the_local_link_drops() {
        let router = Router {
            local_key: KEY.into(),
            security: SecurityData::new("k"),
            rpc: Mutex::new(HashMap::new()),
            maps: Mutex::new(HashMap::new()),
            local_ids: Mutex::new(HashMap::new()),
            on_push: Arc::new(|_| {}),
        };
        let (local_tx, local_rx) = mpsc::channel();
        let (newer_tx, newer_rx) = mpsc::channel();
        let (mqtt_tx, mqtt_rx) = mpsc::channel();
        router.rpc.lock().unwrap().insert(7, local_tx);
        router.local_ids.lock().unwrap().insert(7, 1);
        // Sent on a newer channel (generation 2) that is still up.
        router.rpc.lock().unwrap().insert(9, newer_tx);
        router.local_ids.lock().unwrap().insert(9, 2);
        router.rpc.lock().unwrap().insert(8, mqtt_tx);
        // A late signal from the old channel (generation 1).
        router.local_down(1);
        assert_eq!(
            local_rx.try_recv().unwrap(),
            Err("The local connection to the vacuum was lost".to_string())
        );
        // The newer channel's request and an MQTT request keep waiting.
        assert!(newer_rx.try_recv().is_err());
        assert!(router.rpc.lock().unwrap().contains_key(&9));
        assert!(mqtt_rx.try_recv().is_err());
        assert!(router.rpc.lock().unwrap().contains_key(&8));
    }

    #[test]
    fn a_failed_or_panicking_connect_never_leaves_reconnects_blocked() {
        let state = Mutex::new(LocalState::new());
        // A connect that fails: the attempt ends and a later one runs.
        ensure_local_with(&state, |_| Err("unreachable".into()));
        {
            let local = state.lock().unwrap();
            assert!(!local.connecting);
            assert!(
                local.next_attempt > Instant::now(),
                "no backoff after a failure"
            );
        }
        // A connect that panics: same, the guard clears it.
        state.lock().unwrap().next_attempt = Instant::now();
        let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            ensure_local_with(&state, |_| panic!("connect blew up"))
        }));
        assert!(r.is_err());
        let local = state.lock().unwrap();
        assert!(
            !local.connecting,
            "a panicking connect left `connecting` set"
        );
        assert!(local.next_attempt > Instant::now());
        drop(local);
        // And the next retry really happens.
        state.lock().unwrap().next_attempt = Instant::now();
        let mut ran = false;
        ensure_local_with(&state, |_| {
            ran = true;
            Err("still down".into())
        });
        assert!(ran);
    }

    /// A fake vacuum that takes any number of connections, answers hello on
    /// each, and counts how many are still open.
    fn counting_device() -> (String, Arc<Mutex<(usize, usize)>>) {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap().to_string();
        let counts = Arc::new(Mutex::new((0usize, 0usize))); // (accepted, closed)
        let c = counts.clone();
        std::thread::spawn(move || {
            for sock in listener.incoming().flatten() {
                c.lock().unwrap().0 += 1;
                let c = c.clone();
                std::thread::spawn(move || {
                    let mut sock = sock;
                    let mut frames = protocol::FrameBuffer::default();
                    let mut chunk = [0u8; 4096];
                    loop {
                        match sock.read(&mut chunk) {
                            Ok(0) | Err(_) => break,
                            Ok(n) => frames.push(&chunk[..n]),
                        }
                        while let Some(frame) = frames.next_frame() {
                            let msg = protocol::decode_frame(&frame, KEY, None).unwrap();
                            if msg.protocol == protocol::HELLO_REQUEST {
                                let reply = Message {
                                    seq: msg.seq,
                                    random: 7,
                                    ..Message::new(protocol::HELLO_RESPONSE, None)
                                };
                                let _ = sock
                                    .write_all(&protocol::encode(&reply, KEY, true, None).unwrap());
                            }
                        }
                    }
                    c.lock().unwrap().1 += 1;
                });
            }
        });
        (addr, counts)
    }

    #[test]
    fn racing_reconnects_leave_exactly_one_open_channel() {
        let (addr, counts) = counting_device();
        let state = Arc::new(Mutex::new(LocalState::new()));
        let barrier = Arc::new(std::sync::Barrier::new(2));
        let racers: Vec<_> = (0..2)
            .map(|_| {
                let (state, barrier, addr) = (state.clone(), barrier.clone(), addr.clone());
                std::thread::spawn(move || {
                    barrier.wait();
                    ensure_local_with(&state, |_| {
                        // Slow enough that the two attempts overlap.
                        std::thread::sleep(Duration::from_millis(200));
                        LocalChannel::connect_addr(&addr, KEY, Arc::new(|_| {})).map_err(|e| e.0)
                    });
                })
            })
            .collect();
        for r in racers {
            r.join().unwrap();
        }
        std::thread::sleep(Duration::from_millis(300));
        let (accepted, closed) = *counts.lock().unwrap();
        assert_eq!(
            accepted - closed,
            1,
            "{accepted} connections, {closed} closed"
        );
        assert_eq!(accepted, 1, "both racers connected");
        let local = state.lock().unwrap();
        assert!(local.channel.as_ref().unwrap().is_connected());
        local.channel.as_ref().unwrap().close();
    }

    /// A fake Roborock MQTT broker (plain TCP): accepts the session, and
    /// answers every RPC published to `rr/m/i/...` with `["ok"]` on the
    /// matching `rr/m/o/...` topic. Returns its port and how many RPCs it saw.
    fn fake_broker() -> (u16, Arc<Mutex<usize>>) {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let seen = Arc::new(Mutex::new(0usize));
        let s2 = seen.clone();
        std::thread::spawn(move || {
            let (mut sock, _) = listener.accept().unwrap();
            let mut buf = Vec::new();
            let mut chunk = [0u8; 8192];
            loop {
                let n = match sock.read(&mut chunk) {
                    Ok(0) | Err(_) => return,
                    Ok(n) => n,
                };
                buf.extend_from_slice(&chunk[..n]);
                while let Ok(Some((header, body, used))) = mqtt::split_packet(&buf) {
                    buf.drain(..used);
                    match header >> 4 {
                        1 => sock.write_all(&[0x20, 0x03, 0x00, 0x00, 0x00]).unwrap(),
                        8 => {
                            let (a, b) = (body[0], body[1]);
                            sock.write_all(&[0x90, 0x04, a, b, 0x00, 0x00]).unwrap();
                        }
                        3 => {
                            let (topic, payload, _) = mqtt::parse_publish(header, &body).unwrap();
                            let msg = protocol::decode_frame(payload, KEY, None).unwrap();
                            let doc: Value =
                                serde_json::from_slice(msg.payload.as_ref().unwrap()).unwrap();
                            let inner: Value =
                                serde_json::from_str(doc["dps"]["101"].as_str().unwrap()).unwrap();
                            *s2.lock().unwrap() += 1;
                            let point = json!({"id": inner["id"], "result": ["ok"]}).to_string();
                            let reply = Message::new(
                                protocol::RPC_RESPONSE,
                                Some(json!({"dps": {"102": point}}).to_string().into_bytes()),
                            );
                            let wire = protocol::encode(&reply, KEY, false, None).unwrap();
                            let out = topic.replacen("rr/m/i/", "rr/m/o/", 1);
                            sock.write_all(&mqtt::publish_packet(&out, &wire)).unwrap();
                        }
                        12 => sock.write_all(&[0xD0, 0x00]).unwrap(),
                        _ => {}
                    }
                }
            }
        });
        (port, seen)
    }

    /// A fake vacuum on the local port: answers hello, then drops the
    /// connection the moment a command arrives, never answering it.
    fn vacuum_that_dies_mid_command() -> u16 {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        std::thread::spawn(move || {
            let (mut sock, _) = listener.accept().unwrap();
            let mut frames = protocol::FrameBuffer::default();
            let mut chunk = [0u8; 4096];
            loop {
                let n = match sock.read(&mut chunk) {
                    Ok(0) | Err(_) => return,
                    Ok(n) => n,
                };
                frames.push(&chunk[..n]);
                while let Some(frame) = frames.next_frame() {
                    let msg = protocol::decode_frame(&frame, KEY, None).unwrap();
                    match msg.protocol {
                        protocol::HELLO_REQUEST => {
                            let reply = Message {
                                seq: msg.seq,
                                random: 7,
                                ..Message::new(protocol::HELLO_RESPONSE, None)
                            };
                            sock.write_all(&protocol::encode(&reply, KEY, true, None).unwrap())
                                .unwrap();
                        }
                        protocol::GENERAL_REQUEST => {
                            let _ = sock.shutdown(std::net::Shutdown::Both);
                            return;
                        }
                        _ => {}
                    }
                }
            }
        });
        port
    }

    #[test]
    fn a_command_whose_local_link_dies_falls_back_to_mqtt_at_once() {
        let (broker_port, seen) = fake_broker();
        let local_port = vacuum_that_dies_mid_command();
        let session = mqtt::Session::connect(
            mqtt::Options {
                host: "127.0.0.1".into(),
                port: broker_port,
                tls: false,
                username: "user".into(),
                password: "pw".into(),
                client_id: "test".into(),
            },
            None,
        )
        .unwrap();
        let device = HomeDevice {
            duid: "d1".into(),
            name: "Rocky".into(),
            local_key: KEY.into(),
            pv: "1.0".into(),
            model: "roborock.vacuum.a70".into(),
            category: "robot.vacuum.cleaner".into(),
        };
        let router = Arc::new(Router {
            local_key: KEY.into(),
            security: SecurityData::new("k"),
            rpc: Mutex::new(HashMap::new()),
            maps: Mutex::new(HashMap::new()),
            local_ids: Mutex::new(HashMap::new()),
            on_push: Arc::new(|_| {}),
        });
        let r = router.clone();
        let sub_topic = "rr/m/o/u/user/d1".to_string();
        let sub_id = session
            .subscribe(&sub_topic, Arc::new(move |p: &[u8]| r.mqtt_payload(p)))
            .unwrap();
        let mut cache = Cache::default();
        cache.set_device_value("d1", "network_info", json!({"ip": "127.0.0.1"}));
        let dir =
            std::env::temp_dir().join(format!("rr-e2e-{}", crypto::hex(&crypto::random_bytes(4))));
        let link = Link {
            device,
            region: "us".into(),
            mqtt: session,
            pub_topic: "rr/m/i/u/user/d1".into(),
            sub_topic,
            sub_id,
            router,
            local: Mutex::new(LocalState::new()),
            local_port,
            cache: Mutex::new(cache),
            cache_path: dir.join("home.json"),
            last_map: Mutex::new(None),
        };
        link.ensure_local();
        assert!(
            link.is_local_connected(),
            "the local link should be up first"
        );
        let started = Instant::now();
        let result = link.rpc("app_pause", None);
        let took = started.elapsed();
        assert_eq!(
            result,
            Ok(json!(["ok"])),
            "the command must succeed over MQTT"
        );
        assert!(
            took < Duration::from_secs(3),
            "the command waited {took:?} on the dead local link"
        );
        assert_eq!(*seen.lock().unwrap(), 1, "MQTT carried the command");
        assert!(!link.is_local_connected());
        link.close();
        let _ = std::fs::remove_dir_all(dir);
    }
}
