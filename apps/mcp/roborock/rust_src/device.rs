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

//! The vacuum itself: one connection, a status snapshot, the map, and commands.

use crate::codes::{self, Features};
use crate::config::{self, Credentials};
use crate::link::{home_rooms, HomeDevice, Link, OpenOptions};
use crate::mapimg;
use serde_json::{json, Map, Value};
use std::collections::{HashMap, HashSet};
use std::fmt;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

pub const SIMPLE_ACTIONS: &[(&str, &str)] = &[
    ("start", "app_start"),
    ("pause", "app_pause"),
    ("stop", "app_stop"),
    ("dock", "app_charge"),
    ("find", "find_me"),
    ("wash_start", "app_start_wash"),
    ("wash_stop", "app_stop_wash"),
];

pub const ACTIONS: &[&str] = &[
    "start",
    "pause",
    "stop",
    "dock",
    "find",
    "wash_start",
    "wash_stop",
    "resume",
    "clean_rooms",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DeviceError {
    Rejected(String),
    UnknownAction(String),
}

impl DeviceError {
    pub fn rejected(msg: impl Into<String>) -> Self {
        Self::Rejected(msg.into())
    }

    pub fn unknown_action(msg: impl Into<String>) -> Self {
        Self::UnknownAction(msg.into())
    }

    pub fn is_unknown_action(&self) -> bool {
        matches!(self, Self::UnknownAction(_))
    }

    pub fn message(&self) -> &str {
        match self {
            Self::Rejected(m) | Self::UnknownAction(m) => m,
        }
    }
}

impl fmt::Display for DeviceError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.message())
    }
}

impl std::error::Error for DeviceError {}

pub type UpdateCallback = Arc<dyn Fn(Map<String, Value>) + Send + Sync>;

pub trait Vacuum: Send + Sync {
    fn connect(&self) -> Result<(), DeviceError>;
    fn close(&self) -> Result<(), DeviceError>;
    fn status(&self) -> Result<Map<String, Value>, DeviceError>;
    fn map_png(&self) -> Result<Option<Vec<u8>>, DeviceError>;
    fn command(
        &self,
        action: &str,
        params: Option<&Map<String, Value>>,
    ) -> Result<Value, DeviceError>;
    fn on_update(&self, callback: UpdateCallback);
    fn credentials_rejected(&self) -> bool;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Room {
    pub id: i64,
    pub name: String,
}

impl Room {
    pub fn new(id: i64, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
        }
    }

    pub fn to_value(&self) -> Value {
        json!({
            "id": self.id,
            "name": self.name,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceCandidate {
    pub duid: String,
    pub name: String,
    pub model: Option<String>,
    pub is_local_connected: bool,
    pub supports_v1: bool,
}

#[derive(Debug, Clone)]
pub struct RawVacuumStatus {
    pub state: Option<i64>,
    pub state_name: Option<String>,
    pub battery: Option<i64>,
    pub error_code: Option<i64>,
    pub error_code_name: Option<String>,
    pub dock_error_status: Option<i64>,
    pub clean_time: Option<i64>,
    pub square_meter_clean_area: Option<f64>,
    pub clean_percent: Option<i64>,
    pub in_cleaning: Option<i64>,
    pub in_returning: bool,
    pub fan_speed_name: Result<Option<String>, String>,
    pub water_mode_name: Result<Option<String>, String>,
    pub mop_route_name: Result<Option<String>, String>,
}

impl Default for RawVacuumStatus {
    fn default() -> Self {
        Self {
            state: Some(8),
            state_name: Some("charging".to_string()),
            battery: Some(87),
            error_code: Some(0),
            error_code_name: Some("none".to_string()),
            dock_error_status: None,
            clean_time: Some(600),
            square_meter_clean_area: Some(12.5),
            clean_percent: None,
            in_cleaning: Some(0),
            in_returning: false,
            fan_speed_name: Ok(Some("balanced".to_string())),
            water_mode_name: Ok(None),
            mop_route_name: Ok(None),
        }
    }
}

/// Turn a `get_status` reply (and the model's features) into the fields the
/// snapshot reports, as python-roborock's `StatusTrait` derives them.
pub fn raw_status_from(
    doc: &Map<String, Value>,
    features: &Features,
    region: &str,
) -> RawVacuumStatus {
    let int = |k: &str| -> Option<i64> {
        match doc.get(k)? {
            Value::Number(n) => n.as_i64().or_else(|| n.as_f64().map(|f| f as i64)),
            Value::String(s) => s.parse().ok(),
            Value::Bool(b) => Some(*b as i64),
            _ => None,
        }
    };
    let state = int("state");
    let error_code = int("error_code");
    let fan = int("fan_power");
    let water = int("water_box_mode");
    let mop = int("mop_mode");
    RawVacuumStatus {
        state,
        // An unknown state code reads "unknown", as RoborockStateCode does.
        state_name: state.map(|c| codes::state_name(c).unwrap_or("unknown").to_string()),
        battery: int("battery"),
        error_code,
        error_code_name: error_code.and_then(codes::error_name).map(str::to_string),
        dock_error_status: int("dock_error_status"),
        clean_time: int("clean_time"),
        square_meter_clean_area: int("clean_area")
            .map(|a| (a as f64 / 1_000_000.0 * 10.0).round() / 10.0),
        clean_percent: int("clean_percent"),
        in_cleaning: int("in_cleaning"),
        in_returning: int("in_returning").unwrap_or(0) != 0,
        fan_speed_name: Ok(fan
            .and_then(|c| features.fan_speed_name(c))
            .map(str::to_string)),
        water_mode_name: Ok(water
            .and_then(|c| features.water_mode_name(c))
            .map(str::to_string)),
        mop_route_name: Ok(mop
            .and_then(|c| features.mop_route_name(c, region))
            .map(str::to_string)),
    }
}

/// The data points a V1 vacuum pushes, by the status field they update
/// (`StatusV2` fields with `dps` metadata).
const PUSHED_FIELDS: &[(&str, &str)] = &[
    ("120", "error_code"),
    ("121", "state"),
    ("122", "battery"),
    ("123", "fan_power"),
    ("124", "water_box_mode"),
    ("133", "charge_status"),
    ("134", "dry_status"),
];

struct Live {
    /// None only in tests, which drive the push path without a network.
    link: Option<Arc<Link>>,
    region: String,
    features: Option<Features>,
    status_doc: Map<String, Value>,
    room_names: HashMap<String, String>,
    discovered_iot_ids: HashSet<String>,
}

struct Inner {
    connected_device: Mutex<Option<DeviceCandidate>>,
    raw_status: Mutex<Option<RawVacuumStatus>>,
    rooms: Mutex<Vec<Room>>,
    listeners: Mutex<Vec<UpdateCallback>>,
    credentials_rejected: Arc<AtomicBool>,
    live: Mutex<Option<Live>>,
}

impl Inner {
    fn snapshot(&self) -> Result<Map<String, Value>, DeviceError> {
        let local = self
            .live
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .and_then(|l| l.link.as_ref())
            .map(|l| l.is_local_connected());
        let mut dev_guard = self
            .connected_device
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if let (Some(dev), Some(local)) = (dev_guard.as_mut(), local) {
            dev.is_local_connected = local;
        }
        let status_guard = self.raw_status.lock().unwrap_or_else(|e| e.into_inner());
        let rooms_guard = self.rooms.lock().unwrap_or_else(|e| e.into_inner());
        let device = dev_guard
            .as_ref()
            .ok_or_else(|| DeviceError::rejected("Not connected to the vacuum yet."))?;
        let status = status_guard
            .as_ref()
            .ok_or_else(|| DeviceError::rejected("Not connected to the vacuum yet."))?;
        Ok(build_snapshot(device, status, &rooms_guard))
    }

    #[cfg(test)]
    fn live_status_for_test(&self, status_doc: Map<String, Value>, features: Features) {
        *self.live.lock().unwrap_or_else(|e| e.into_inner()) = Some(Live {
            link: None,
            region: "us".into(),
            features: Some(features),
            status_doc,
            room_names: HashMap::new(),
            discovered_iot_ids: HashSet::new(),
        });
    }

    /// A status push from the device: merge it, then tell the listeners.
    fn on_push(&self, points: Map<String, Value>) {
        let updated = {
            let mut live = self.live.lock().unwrap_or_else(|e| e.into_inner());
            let Some(live) = live.as_mut() else { return };
            let mut changed = false;
            for (dp, field) in PUSHED_FIELDS {
                if let Some(v) = points.get(*dp) {
                    if live.status_doc.get(*field) != Some(v) {
                        live.status_doc.insert(field.to_string(), v.clone());
                        changed = true;
                    }
                }
            }
            if !changed || live.status_doc.is_empty() {
                return;
            }
            let features = live.features.unwrap_or_default();
            raw_status_from(&live.status_doc, &features, &live.region)
        };
        *self.raw_status.lock().unwrap_or_else(|e| e.into_inner()) = Some(updated);
        if let Ok(snapshot) = self.snapshot() {
            let listeners = self
                .listeners
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .clone();
            for listener in listeners {
                listener(snapshot.clone());
            }
        }
    }
}

fn build_snapshot(
    device: &DeviceCandidate,
    status: &RawVacuumStatus,
    rooms: &[Room],
) -> Map<String, Value> {
    let error_code = status.error_code.filter(|&c| c != 0);
    let dock_error = status.dock_error_status.filter(|&c| c != 0);
    let error_name = if error_code.is_some() {
        status
            .error_code_name
            .clone()
            .map(Value::String)
            .unwrap_or(Value::Null)
    } else {
        Value::Null
    };
    let label = |v: &Result<Option<String>, String>| {
        v.as_ref()
            .ok()
            .and_then(|v| v.clone())
            .map(Value::String)
            .unwrap_or(Value::Null)
    };
    let rooms_val: Vec<Value> = rooms.iter().map(Room::to_value).collect();
    let doc = json!({
        "device": {
            "id": device.duid,
            "name": device.name,
            "model": device.model,
            "local": device.is_local_connected,
        },
        "state": status.state_name,
        "state_code": status.state,
        "battery": status.battery,
        "error": error_name,
        "error_code": error_code,
        "dock_error_code": dock_error,
        "clean_time_s": status.clean_time,
        "clean_area_m2": status.square_meter_clean_area,
        "clean_percent": status.clean_percent,
        "in_cleaning": status.in_cleaning.unwrap_or(0) != 0,
        "in_returning": status.in_returning,
        "fan_speed": label(&status.fan_speed_name),
        "water_mode": label(&status.water_mode_name),
        "mop_route": label(&status.mop_route_name),
        "rooms": rooms_val,
    });
    doc.as_object().cloned().unwrap_or_default()
}

/// `RoomsConverter.extract_segment_map`: `[[segment, iot_id], ...]` or a
/// single flat pair, as (segment id, iot id).
pub fn segment_map(reply: &Value) -> Vec<(i64, String)> {
    let Some(list) = reply.as_array() else {
        return Vec::new();
    };
    let iot = |v: &Value| match v {
        Value::String(s) => s.clone(),
        other => other.to_string(),
    };
    if list.len() == 2 && !list[0].is_array() {
        return list[0]
            .as_i64()
            .map(|seg| vec![(seg, iot(&list[1]))])
            .unwrap_or_default();
    }
    let mut out: Vec<(i64, String)> = Vec::new();
    for part in list {
        let Some(pair) = part.as_array().filter(|p| p.len() >= 2) else {
            continue;
        };
        let Some(seg) = pair[0].as_i64() else {
            continue;
        };
        if let Some(existing) = out.iter_mut().find(|(s, _)| *s == seg) {
            existing.1 = iot(&pair[1]);
        } else {
            out.push((seg, iot(&pair[1])));
        }
    }
    out
}

/// A V1-protocol Roborock vacuum, reached over the cloud MQTT broker and,
/// when it can be, the local network.
pub struct RoborockVacuum {
    pub credentials: Credentials,
    pub device_id: Option<String>,
    pub cache_file: PathBuf,
    inner: Arc<Inner>,
}

impl RoborockVacuum {
    pub fn new(
        credentials: Credentials,
        device_id: Option<String>,
        cache_file: Option<PathBuf>,
    ) -> Self {
        Self {
            credentials,
            device_id,
            cache_file: cache_file.unwrap_or_else(config::cache_path),
            inner: Arc::new(Inner {
                connected_device: Mutex::new(None),
                raw_status: Mutex::new(None),
                rooms: Mutex::new(Vec::new()),
                listeners: Mutex::new(Vec::new()),
                credentials_rejected: Arc::new(AtomicBool::new(false)),
                live: Mutex::new(None),
            }),
        }
    }

    pub fn set_test_state(
        &self,
        device: DeviceCandidate,
        status: RawVacuumStatus,
        rooms: Vec<Room>,
    ) {
        *self
            .inner
            .connected_device
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = Some(device);
        *self
            .inner
            .raw_status
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = Some(status);
        *self.inner.rooms.lock().unwrap_or_else(|e| e.into_inner()) = rooms;
    }

    pub fn select_device<'a>(
        &self,
        devices: &'a [DeviceCandidate],
    ) -> Result<&'a DeviceCandidate, DeviceError> {
        select(self.device_id.as_deref(), devices)
    }

    pub fn resolve_action(
        &self,
        action: &str,
        params: &Map<String, Value>,
    ) -> Result<(String, Option<Value>), DeviceError> {
        let status_guard = self
            .inner
            .raw_status
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let status = status_guard
            .as_ref()
            .ok_or_else(|| DeviceError::rejected("Not connected to the vacuum yet."))?;
        for &(name, raw) in SIMPLE_ACTIONS {
            if action == name {
                return Ok((raw.to_string(), None));
            }
        }
        if action == "resume" {
            let raw = match status.in_cleaning.unwrap_or(0) {
                2 => "resume_zoned_clean",
                3 => "resume_segment_clean",
                _ => "app_start",
            };
            return Ok((raw.to_string(), None));
        }
        if action == "clean_rooms" {
            let wanted = params
                .get("rooms")
                .and_then(|v| v.as_array())
                .cloned()
                .unwrap_or_default();
            let rooms = self.inner.rooms.lock().unwrap_or_else(|e| e.into_inner());
            let segments = resolve_rooms(&wanted, &rooms)?;
            let repeat = params.get("repeat").and_then(|v| v.as_i64()).unwrap_or(1);
            if !(1..=3).contains(&repeat) {
                return Err(DeviceError::rejected("repeat must be 1, 2 or 3."));
            }
            return Ok((
                "app_segment_clean".to_string(),
                Some(json!([{"segments": segments, "repeat": repeat}])),
            ));
        }
        Err(DeviceError::unknown_action(format!(
            "Unknown action {action:?}. Supported: {}.",
            ACTIONS.join(", ")
        )))
    }

    pub fn snapshot(&self) -> Result<Map<String, Value>, DeviceError> {
        self.inner.snapshot()
    }

    fn link(&self) -> Option<Arc<Link>> {
        self.inner
            .live
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .and_then(|l| l.link.clone())
    }

    /// `DeviceFeaturesTrait.refresh`: the cached init status, else ask.
    fn ensure_features(&self, link: &Link) -> Result<Features, DeviceError> {
        if let Some(f) = self
            .inner
            .live
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .and_then(|l| l.features)
        {
            return Ok(f);
        }
        let model = link.device.model.clone();
        let from_cache = link
            .cached("init_status")
            .and_then(|v| Features::from_init_status(&v, &model));
        let features = match from_cache {
            Some(f) => f,
            None => {
                let reply = link.rpc("app_get_init_status", None).map_err(|e| {
                    DeviceError::rejected(format!("The vacuum did not answer: {e}"))
                })?;
                let f = Features::from_init_status(&reply, &model).ok_or_else(|| {
                    DeviceError::rejected(format!(
                        "The vacuum did not answer: unexpected AppInitStatus reply {reply}"
                    ))
                })?;
                link.remember("init_status", reply);
                f
            }
        };
        if let Some(live) = self
            .inner
            .live
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_mut()
        {
            live.features = Some(features);
        }
        Ok(features)
    }

    /// `RoomsTrait.refresh`; failures only leave the room list empty.
    fn load_rooms(&self, link: &Link) {
        let Ok(reply) = link.rpc("get_room_mapping", None) else {
            return;
        };
        let segments = segment_map(&reply);
        let (mut names, discovered) = {
            let live = self.inner.live.lock().unwrap_or_else(|e| e.into_inner());
            let Some(live) = live.as_ref() else { return };
            (live.room_names.clone(), live.discovered_iot_ids.clone())
        };
        let new_ids: HashSet<String> = segments
            .iter()
            .map(|(_, iot)| iot.clone())
            .filter(|iot| !names.contains_key(iot))
            .collect();
        if new_ids.difference(&discovered).next().is_some() {
            if let Ok(rooms) = Link::fetch_rooms(&self.credentials) {
                if !rooms.is_empty() {
                    names = rooms.iter().cloned().collect();
                    link.set_home_rooms(&rooms);
                }
            }
        }
        if let Some(live) = self
            .inner
            .live
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_mut()
        {
            live.room_names = names.clone();
            live.discovered_iot_ids.extend(new_ids);
        }
        let rooms: Vec<Room> = segments
            .into_iter()
            .map(|(seg, iot)| {
                Room::new(
                    seg,
                    names
                        .get(&iot)
                        .cloned()
                        .unwrap_or_else(|| format!("Room {seg}")),
                )
            })
            .collect();
        *self.inner.rooms.lock().unwrap_or_else(|e| e.into_inner()) = rooms;
    }
}

/// python-roborock's `_select`: a named device, else the first V1 vacuum.
pub fn select<'a>(
    wanted: Option<&str>,
    devices: &'a [DeviceCandidate],
) -> Result<&'a DeviceCandidate, DeviceError> {
    let vacuums: Vec<&DeviceCandidate> = devices.iter().filter(|d| d.supports_v1).collect();
    if let Some(wanted_id) = wanted {
        for device in devices {
            if wanted_id == device.duid || wanted_id == device.name {
                if !device.supports_v1 {
                    return Err(DeviceError::rejected(format!(
                        "{} uses a protocol this version does not support yet.",
                        device.name
                    )));
                }
                return Ok(device);
            }
        }
        return Err(DeviceError::rejected(format!(
            "No device named or identified as {wanted_id:?} on this account."
        )));
    }
    if vacuums.is_empty() {
        if !devices.is_empty() {
            return Err(DeviceError::rejected(
                "The devices on this account use a protocol this version does not support yet.",
            ));
        }
        return Err(DeviceError::rejected(
            "This Roborock account has no devices.",
        ));
    }
    if vacuums.len() > 1 {
        let names: Vec<&str> = vacuums.iter().map(|d| d.name.as_str()).collect();
        eprintln!(
            "Several vacuums found ({}); using {}. Set {} to choose.",
            names.join(", "),
            vacuums[0].name,
            config::DEVICE_ENV
        );
    }
    Ok(vacuums[0])
}

fn candidate(d: &HomeDevice) -> DeviceCandidate {
    DeviceCandidate {
        duid: d.duid.clone(),
        name: d.name.clone(),
        model: Some(d.model.clone()).filter(|m| !m.is_empty()),
        is_local_connected: false,
        supports_v1: d.is_v1_vacuum(),
    }
}

impl Vacuum for RoborockVacuum {
    fn connect(&self) -> Result<(), DeviceError> {
        if let Some(parent) = self.cache_file.parent() {
            let _ = config::ensure_private_dir(parent);
        }
        if self.link().is_some() {
            return Ok(());
        }
        let wanted = self.device_id.clone();
        let inner = Arc::downgrade(&self.inner);
        let link = Link::open(
            &self.credentials,
            OpenOptions {
                cache_path: self.cache_file.clone(),
                unauthorized: self.inner.credentials_rejected.clone(),
                on_push: Arc::new(move |points| {
                    if let Some(inner) = inner.upgrade() {
                        inner.on_push(points);
                    }
                }),
                select: Box::new(move |devices| {
                    let candidates: Vec<DeviceCandidate> = devices.iter().map(candidate).collect();
                    let chosen = select(wanted.as_deref(), &candidates)
                        .map_err(|e| e.message().to_string())?;
                    Ok(devices
                        .iter()
                        .find(|d| d.duid == chosen.duid)
                        .cloned()
                        .expect("the chosen device came from this list"))
                }),
            },
        )
        .map_err(|e| {
            if e.message.contains("protocol this version")
                || e.message.contains("no devices")
                || e.message.contains("No device named")
            {
                DeviceError::rejected(e.message)
            } else {
                DeviceError::rejected(format!("Could not reach the Roborock cloud: {}", e.message))
            }
        })?;
        let link = Arc::new(link);
        let room_names = home_rooms(&link.home_data());
        *self
            .inner
            .connected_device
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = Some(candidate(&link.device));
        *self.inner.live.lock().unwrap_or_else(|e| e.into_inner()) = Some(Live {
            link: Some(link.clone()),
            region: link.region.clone(),
            features: None,
            status_doc: Map::new(),
            room_names,
            discovered_iot_ids: HashSet::new(),
        });
        // Feature discovery may fail while the vacuum is offline; status()
        // retries it, as python-roborock's connect loop does.
        let _ = self.ensure_features(&link);
        Ok(())
    }

    fn close(&self) -> Result<(), DeviceError> {
        self.inner
            .listeners
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clear();
        if let Some(link) = self
            .inner
            .live
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take()
            .and_then(|l| l.link)
        {
            link.close();
        }
        *self
            .inner
            .connected_device
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = None;
        *self
            .inner
            .raw_status
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = None;
        Ok(())
    }

    fn status(&self) -> Result<Map<String, Value>, DeviceError> {
        let Some(link) = self.link() else {
            // Not connected: a snapshot from set_test_state, or the error.
            return self.snapshot();
        };
        let features = self.ensure_features(&link)?;
        let reply = link
            .rpc("get_status", None)
            .map_err(|e| DeviceError::rejected(format!("The vacuum did not answer: {e}")))?;
        let doc = match &reply {
            Value::Array(a) => a.first().and_then(Value::as_object).cloned(),
            Value::Object(o) => Some(o.clone()),
            _ => None,
        }
        .ok_or_else(|| {
            DeviceError::rejected(format!(
                "The vacuum did not answer: unexpected status reply {reply}"
            ))
        })?;
        let raw = raw_status_from(&doc, &features, &link.region);
        if let Some(live) = self
            .inner
            .live
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_mut()
        {
            live.status_doc = doc;
        }
        *self
            .inner
            .raw_status
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = Some(raw);
        if self
            .inner
            .rooms
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .is_empty()
        {
            self.load_rooms(&link);
        }
        self.snapshot()
    }

    fn map_png(&self) -> Result<Option<Vec<u8>>, DeviceError> {
        if self
            .inner
            .raw_status
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .is_none()
        {
            return Err(DeviceError::rejected("Not connected to the vacuum yet."));
        }
        let Some(link) = self.link() else {
            return Ok(None);
        };
        let (raw, changed) = link
            .map()
            .map_err(|e| DeviceError::rejected(format!("Could not fetch the map: {e}")))?;
        if !changed {
            return Ok(link.last_png());
        }
        let png = mapimg::map_png(&raw)
            .map_err(|e| DeviceError::rejected(format!("Could not fetch the map: {e}")))?;
        link.set_last_map(raw, png.clone());
        Ok(Some(png))
    }

    fn command(
        &self,
        action: &str,
        params: Option<&Map<String, Value>>,
    ) -> Result<Value, DeviceError> {
        let empty = Map::new();
        let params = params.unwrap_or(&empty);
        let (raw, raw_params) = self.resolve_action(action, params)?;
        let link = self
            .link()
            .ok_or_else(|| DeviceError::rejected("Not connected to the vacuum yet."))?;
        link.rpc(&raw, raw_params)
            .map_err(|e| DeviceError::rejected(format!("The vacuum refused '{action}': {e}")))
    }

    fn on_update(&self, callback: UpdateCallback) {
        self.inner
            .listeners
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push(callback);
    }

    fn credentials_rejected(&self) -> bool {
        self.inner.credentials_rejected.load(Ordering::SeqCst)
    }
}

pub fn resolve_rooms(wanted: &[Value], known: &[Room]) -> Result<Vec<i64>, DeviceError> {
    if wanted.is_empty() {
        return Err(DeviceError::rejected(
            "clean_rooms needs at least one room.",
        ));
    }
    let mut segments = Vec::new();
    for item in wanted {
        let text = match item {
            Value::String(s) => s.trim().to_string(),
            Value::Number(n) => n.to_string(),
            other => other.to_string().trim().to_string(),
        };
        let folded = text.to_lowercase();
        if let Some(room) = known.iter().find(|r| r.name.to_lowercase() == folded) {
            if !segments.contains(&room.id) {
                segments.push(room.id);
            }
        } else if let Ok(id) = text.parse::<i64>() {
            if known.iter().any(|r| r.id == id) {
                if !segments.contains(&id) {
                    segments.push(id);
                }
            } else {
                let available = format_available_rooms(known);
                return Err(DeviceError::rejected(format!(
                    "Unknown room {text:?}. Available: {available}."
                )));
            }
        } else {
            let available = format_available_rooms(known);
            return Err(DeviceError::rejected(format!(
                "Unknown room {text:?}. Available: {available}."
            )));
        }
    }
    Ok(segments)
}

fn format_available_rooms(known: &[Room]) -> String {
    if known.is_empty() {
        "none reported by the vacuum".to_string()
    } else {
        known
            .iter()
            .map(|r| r.name.as_str())
            .collect::<Vec<_>>()
            .join(", ")
    }
}

#[cfg(test)]
mod live_tests {
    use super::*;

    fn s7() -> Features {
        Features::from_flags(0, "", "roborock.vacuum.a15")
    }

    #[test]
    fn get_status_replies_become_snapshot_fields() {
        let doc = json!({
            "state": 5, "battery": 64, "clean_time": 1200, "clean_area": 23_456_789,
            "error_code": 0, "in_cleaning": 3, "in_returning": 0,
            "fan_power": 105, "water_box_mode": 203, "mop_mode": 301, "dock_error_status": 38
        });
        let raw = raw_status_from(doc.as_object().unwrap(), &s7(), "us");
        assert_eq!(raw.state_name.as_deref(), Some("cleaning"));
        assert_eq!(raw.square_meter_clean_area, Some(23.5));
        assert_eq!(raw.fan_speed_name, Ok(Some("off".to_string())));
        assert_eq!(raw.water_mode_name, Ok(Some("intense".to_string())));
        assert_eq!(raw.mop_route_name, Ok(Some("deep".to_string())));
        assert_eq!(raw.in_cleaning, Some(3));
        assert!(!raw.in_returning);
        assert_eq!(raw.dock_error_status, Some(38));
    }

    #[test]
    fn unknown_codes_do_not_lose_the_snapshot() {
        let doc = json!({"state": 4242, "error_code": 999, "fan_power": 1});
        let raw = raw_status_from(doc.as_object().unwrap(), &s7(), "us");
        assert_eq!(raw.state_name.as_deref(), Some("unknown"));
        assert_eq!(raw.state, Some(4242));
        assert_eq!(raw.error_code, Some(999));
        assert_eq!(raw.error_code_name, None);
        assert_eq!(raw.fan_speed_name, Ok(None));
    }

    #[test]
    fn room_mappings_accept_pairs_and_a_single_flat_pair() {
        assert_eq!(
            segment_map(&json!([[16, "101"], [17, 102], [16, "103"]])),
            vec![(16, "103".to_string()), (17, "102".to_string())]
        );
        assert_eq!(
            segment_map(&json!([18, "104"])),
            vec![(18, "104".to_string())]
        );
        assert!(segment_map(&json!({"oops": 1})).is_empty());
    }

    #[test]
    fn a_status_push_updates_the_snapshot_and_notifies_listeners() {
        let creds = Credentials::new("me@example.com", Map::new());
        let vac = RoborockVacuum::new(creds, None, None);
        let seen = Arc::new(Mutex::new(Vec::new()));
        let sink = seen.clone();
        vac.on_update(Arc::new(move |snap| sink.lock().unwrap().push(snap)));
        vac.set_test_state(
            DeviceCandidate {
                duid: "d".into(),
                name: "Rocky".into(),
                model: Some("roborock.vacuum.a15".into()),
                is_local_connected: false,
                supports_v1: true,
            },
            RawVacuumStatus::default(),
            vec![],
        );
        // Without a live link a push has nothing to merge into.
        vac.inner
            .on_push(json!({"121": 5}).as_object().unwrap().clone());
        assert!(seen.lock().unwrap().is_empty());
        let doc = json!({"state": 8, "battery": 90});
        vac.inner
            .live_status_for_test(doc.as_object().unwrap().clone(), s7());
        vac.inner.on_push(
            json!({"121": 5, "122": 89, "999": 1})
                .as_object()
                .unwrap()
                .clone(),
        );
        let seen = seen.lock().unwrap();
        assert_eq!(seen.len(), 1);
        assert_eq!(seen[0]["state"], "cleaning");
        assert_eq!(seen[0]["battery"], 89);
    }
}
