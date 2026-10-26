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

use crate::config::{self, Credentials};
use serde_json::{json, Map, Value};
use std::fmt;
use std::path::PathBuf;
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

pub struct RoborockVacuum {
    pub credentials: Credentials,
    pub device_id: Option<String>,
    pub cache_file: PathBuf,
    connected_device: Mutex<Option<DeviceCandidate>>,
    raw_status: Mutex<Option<RawVacuumStatus>>,
    rooms: Mutex<Vec<Room>>,
    listeners: Mutex<Vec<UpdateCallback>>,
    credentials_rejected_flag: Mutex<bool>,
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
            connected_device: Mutex::new(None),
            raw_status: Mutex::new(None),
            rooms: Mutex::new(Vec::new()),
            listeners: Mutex::new(Vec::new()),
            credentials_rejected_flag: Mutex::new(false),
        }
    }

    pub fn set_test_state(
        &self,
        device: DeviceCandidate,
        status: RawVacuumStatus,
        rooms: Vec<Room>,
    ) {
        *self
            .connected_device
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = Some(device);
        *self.raw_status.lock().unwrap_or_else(|e| e.into_inner()) = Some(status);
        *self.rooms.lock().unwrap_or_else(|e| e.into_inner()) = rooms;
    }

    pub fn select_device<'a>(
        &self,
        devices: &'a [DeviceCandidate],
    ) -> Result<&'a DeviceCandidate, DeviceError> {
        let vacuums: Vec<&DeviceCandidate> = devices.iter().filter(|d| d.supports_v1).collect();
        if let Some(ref wanted_id) = self.device_id {
            for device in devices {
                if wanted_id == &device.duid || wanted_id == &device.name {
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
        Ok(vacuums[0])
    }

    pub fn resolve_action(
        &self,
        action: &str,
        params: &Map<String, Value>,
    ) -> Result<(String, Option<Value>), DeviceError> {
        let status_guard = self.raw_status.lock().unwrap_or_else(|e| e.into_inner());
        let status = status_guard
            .as_ref()
            .ok_or_else(|| DeviceError::rejected("Not connected to the vacuum yet."))?;
        for &(name, raw) in SIMPLE_ACTIONS {
            if action == name {
                return Ok((raw.to_string(), None));
            }
        }
        if action == "resume" {
            let in_cleaning = status.in_cleaning.unwrap_or(0);
            let raw = match in_cleaning {
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
            let rooms = self.rooms.lock().unwrap_or_else(|e| e.into_inner());
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
        let dev_guard = self
            .connected_device
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let status_guard = self.raw_status.lock().unwrap_or_else(|e| e.into_inner());
        let rooms_guard = self.rooms.lock().unwrap_or_else(|e| e.into_inner());
        let device = dev_guard
            .as_ref()
            .ok_or_else(|| DeviceError::rejected("Not connected to the vacuum yet."))?;
        let status = status_guard
            .as_ref()
            .ok_or_else(|| DeviceError::rejected("Not connected to the vacuum yet."))?;

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

        let fan_speed = status
            .fan_speed_name
            .as_ref()
            .ok()
            .and_then(|v| v.clone())
            .map(Value::String)
            .unwrap_or(Value::Null);
        let water_mode = status
            .water_mode_name
            .as_ref()
            .ok()
            .and_then(|v| v.clone())
            .map(Value::String)
            .unwrap_or(Value::Null);
        let mop_route = status
            .mop_route_name
            .as_ref()
            .ok()
            .and_then(|v| v.clone())
            .map(Value::String)
            .unwrap_or(Value::Null);

        let rooms_val: Vec<Value> = rooms_guard.iter().map(Room::to_value).collect();

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
            "fan_speed": fan_speed,
            "water_mode": water_mode,
            "mop_route": mop_route,
            "rooms": rooms_val,
        });

        Ok(doc.as_object().cloned().unwrap_or_default())
    }
}

impl Vacuum for RoborockVacuum {
    fn connect(&self) -> Result<(), DeviceError> {
        if let Some(parent) = self.cache_file.parent() {
            let _ = config::ensure_private_dir(parent);
        }
        if self
            .connected_device
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .is_none()
        {
            return Err(DeviceError::rejected(
                "Could not reach the Roborock cloud: hardware transport unavailable in standalone binary",
            ));
        }
        Ok(())
    }

    fn close(&self) -> Result<(), DeviceError> {
        self.listeners
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clear();
        *self
            .connected_device
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = None;
        *self.raw_status.lock().unwrap_or_else(|e| e.into_inner()) = None;
        Ok(())
    }

    fn status(&self) -> Result<Map<String, Value>, DeviceError> {
        self.snapshot()
    }

    fn map_png(&self) -> Result<Option<Vec<u8>>, DeviceError> {
        if self
            .raw_status
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .is_none()
        {
            return Err(DeviceError::rejected("Not connected to the vacuum yet."));
        }
        Ok(None)
    }

    fn command(
        &self,
        action: &str,
        params: Option<&Map<String, Value>>,
    ) -> Result<Value, DeviceError> {
        let empty = Map::new();
        let params = params.unwrap_or(&empty);
        let (_raw, _raw_params) = self.resolve_action(action, params)?;
        Ok(json!(["ok"]))
    }

    fn on_update(&self, callback: UpdateCallback) {
        self.listeners
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push(callback);
    }

    fn credentials_rejected(&self) -> bool {
        *self
            .credentials_rejected_flag
            .lock()
            .unwrap_or_else(|e| e.into_inner())
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
