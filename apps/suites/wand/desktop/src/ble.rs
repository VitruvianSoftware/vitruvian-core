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

//! BLE transport worker thread (`btleplug` on a dedicated `tokio` runtime):
//! - Scans for `"Daydream controller"` (`Daydream::NAME`) or service `0xFE55` (`Daydream::SERVICE_UUID`).
//! - Connects and subscribes to notify characteristic `00000001-1000-1000-8000-00805f9b34fb`.
//! - Reads Battery Level (`0x180F` / `0x2A19`) on connect and every 60 seconds.
//! - Streams 20-byte packets with monotonic microsecond timestamps to the input thread.
//! - Automatically reconnects with exponential backoff when `auto_reconnect` is enabled.

use crate::input::InputCommand;
use crate::status::{ConnectionState, Status};
use btleplug::api::{Central, Characteristic, Manager as _, Peripheral as _, ScanFilter};
use btleplug::platform::{Adapter, Manager, Peripheral};
use futures::StreamExt;
use std::sync::{Arc, Mutex, mpsc};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};
use tokio::sync::mpsc as tokio_mpsc;
use uuid::Uuid;
use wand_core::Daydream;
use wand_core::controller::{BATTERY_CHAR_UUID, BATTERY_SERVICE_UUID};

/// Interval between BLE Battery Service (`0x180F` / `0x2A19`) reads (`60 s`).
pub const BATTERY_POLL_INTERVAL: Duration = Duration::from_secs(60);

/// Initial reconnect backoff delay (`1 s`).
pub const INITIAL_BACKOFF: Duration = Duration::from_secs(1);

/// Maximum reconnect backoff delay (`16 s`).
pub const MAX_BACKOFF: Duration = Duration::from_secs(16);

/// Commands sent from the UI or tray to the BLE worker task.
#[derive(Debug, Clone)]
pub enum BleCommand {
    /// Start scanning and connect to a Daydream controller.
    Connect,
    /// Disconnect from the active controller and stop auto-reconnecting until `Connect`.
    Disconnect,
    /// Update the `auto_reconnect` preference.
    SetAutoReconnect(bool),
    /// Shut down the BLE runtime thread.
    Shutdown,
}

/// Checks whether a BLE peripheral's advertised name or service UUIDs match the Daydream controller.
pub fn matches_daydream_peripheral(local_name: Option<&str>, services: &[Uuid]) -> bool {
    if let Some(name) = local_name
        && (name.eq_ignore_ascii_case(Daydream::NAME)
            || name.to_ascii_lowercase().contains("daydream"))
    {
        return true;
    }
    if let Ok(daydream_service) = Uuid::parse_str(Daydream::SERVICE_UUID)
        && services.contains(&daydream_service)
    {
        return true;
    }
    false
}

/// Computes the next exponential backoff duration (`1s -> 2s -> 4s -> 8s -> 16s`).
pub fn next_backoff(current: Duration) -> Duration {
    (current * 2).min(MAX_BACKOFF).max(INITIAL_BACKOFF)
}

/// Probes whether a Bluetooth adapter is visible (used by `wand doctor`).
///
/// On macOS, calling `CBCentralManager` (`btleplug::platform::Manager::new`) from an unbundled
/// command-line binary (such as `bazel run //apps/suites/wand/desktop:wand -- doctor`) triggers a
/// fatal TCC `SIGABRT` unless launched from a signed `.app` bundle with `NSBluetoothAlwaysUsageDescription`.
/// When running outside an `.app` bundle on macOS, we probe the Bluetooth controller via `system_profiler`.
pub async fn probe_bluetooth_adapter() -> Result<String, String> {
    #[cfg(target_os = "macos")]
    {
        let in_app_bundle = std::env::current_exe()
            .ok()
            .and_then(|p| p.to_str().map(|s| s.contains(".app/Contents/MacOS/")))
            .unwrap_or(false);
        if !in_app_bundle {
            let output = std::process::Command::new("system_profiler")
                .arg("SPBluetoothDataType")
                .output()
                .map_err(|e| format!("failed to run system_profiler: {e}"))?;
            let stdout = String::from_utf8_lossy(&output.stdout);
            if stdout.contains("Bluetooth Controller") || stdout.contains("State:") {
                let state = stdout
                    .lines()
                    .find_map(|l| l.trim().strip_prefix("State:"))
                    .map(str::trim)
                    .unwrap_or("On");
                return Ok(format!(
                    "present (macOS CoreBluetooth controller, state: {state})"
                ));
            }
            return Err("no macOS Bluetooth controller reported".to_string());
        }
    }

    let manager = Manager::new()
        .await
        .map_err(|e| format!("Bluetooth manager unavailable: {e}"))?;
    let adapters = manager
        .adapters()
        .await
        .map_err(|e| format!("Failed to list Bluetooth adapters: {e}"))?;
    if let Some(first) = adapters.first() {
        let info = first
            .adapter_info()
            .await
            .unwrap_or_else(|_| "Bluetooth LE adapter".to_string());
        Ok(format!("present ({info})"))
    } else {
        Err("no Bluetooth LE adapter found".to_string())
    }
}

/// Spawns the dedicated `tokio` runtime thread managing BLE scanning, connection,
/// packet streaming, battery polling, and auto-reconnection.
pub fn spawn_ble_thread(
    auto_reconnect: bool,
    input_tx: mpsc::Sender<InputCommand>,
    status: Arc<Mutex<Status>>,
) -> (tokio_mpsc::UnboundedSender<BleCommand>, JoinHandle<()>) {
    let (cmd_tx, cmd_rx) = tokio_mpsc::unbounded_channel::<BleCommand>();
    let handle = thread::Builder::new()
        .name("wand-ble".to_string())
        .spawn(move || {
            let rt = tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build()
                .expect("failed to build tokio runtime for wand-ble");
            rt.block_on(ble_worker_loop(auto_reconnect, cmd_rx, input_tx, status));
        })
        .expect("failed to spawn wand-ble thread");
    (cmd_tx, handle)
}

async fn ble_worker_loop(
    mut auto_reconnect: bool,
    mut cmd_rx: tokio_mpsc::UnboundedReceiver<BleCommand>,
    input_tx: mpsc::Sender<InputCommand>,
    status: Arc<Mutex<Status>>,
) {
    let clock_origin = Instant::now();
    let mut want_connected = false;
    let mut backoff = INITIAL_BACKOFF;

    loop {
        if !want_connected {
            let Some(cmd) = cmd_rx.recv().await else {
                break;
            };
            match cmd {
                BleCommand::Connect => {
                    want_connected = true;
                    backoff = INITIAL_BACKOFF;
                }
                BleCommand::Disconnect => {
                    want_connected = false;
                    let _ = input_tx.send(InputCommand::ReleaseAll);
                    if let Ok(mut st) = status.lock() {
                        st.on_disconnected();
                    }
                }
                BleCommand::SetAutoReconnect(val) => {
                    auto_reconnect = val;
                }
                BleCommand::Shutdown => {
                    let _ = input_tx.send(InputCommand::ReleaseAll);
                    break;
                }
            }
            continue;
        }

        if let Ok(mut st) = status.lock() {
            st.connection = ConnectionState::Scanning;
        }

        match connect_and_stream_once(
            &mut cmd_rx,
            &input_tx,
            &status,
            clock_origin,
            &mut auto_reconnect,
            &mut want_connected,
        )
        .await
        {
            Ok(SessionOutcome::Shutdown) => {
                let _ = input_tx.send(InputCommand::ReleaseAll);
                break;
            }
            Ok(SessionOutcome::UserDisconnected) => {
                want_connected = false;
                let _ = input_tx.send(InputCommand::ReleaseAll);
                if let Ok(mut st) = status.lock() {
                    st.on_disconnected();
                }
            }
            Ok(SessionOutcome::ConnectionLost) => {
                let _ = input_tx.send(InputCommand::ReleaseAll);
                if auto_reconnect && want_connected {
                    backoff = INITIAL_BACKOFF;
                    if let Ok(mut st) = status.lock() {
                        st.connection = ConnectionState::Scanning;
                    }
                    if wait_or_handle_cmd(
                        backoff,
                        &mut cmd_rx,
                        &input_tx,
                        &mut auto_reconnect,
                        &mut want_connected,
                        &status,
                    )
                    .await
                    {
                        break;
                    }
                } else {
                    want_connected = false;
                    if let Ok(mut st) = status.lock() {
                        st.on_disconnected();
                    }
                }
            }
            Err(err) => {
                let _ = input_tx.send(InputCommand::ReleaseAll);
                if let Ok(mut st) = status.lock() {
                    st.connection = ConnectionState::Error(err);
                }
                if auto_reconnect && want_connected {
                    if wait_or_handle_cmd(
                        backoff,
                        &mut cmd_rx,
                        &input_tx,
                        &mut auto_reconnect,
                        &mut want_connected,
                        &status,
                    )
                    .await
                    {
                        break;
                    }
                    backoff = next_backoff(backoff);
                } else {
                    want_connected = false;
                }
            }
        }
    }
}

enum SessionOutcome {
    UserDisconnected,
    ConnectionLost,
    Shutdown,
}

async fn wait_or_handle_cmd(
    delay: Duration,
    cmd_rx: &mut tokio_mpsc::UnboundedReceiver<BleCommand>,
    input_tx: &mpsc::Sender<InputCommand>,
    auto_reconnect: &mut bool,
    want_connected: &mut bool,
    status: &Arc<Mutex<Status>>,
) -> bool {
    tokio::select! {
        _ = tokio::time::sleep(delay) => false,
        cmd = cmd_rx.recv() => {
            match cmd {
                Some(BleCommand::Disconnect) => {
                    *want_connected = false;
                    let _ = input_tx.send(InputCommand::ReleaseAll);
                    if let Ok(mut st) = status.lock() {
                        st.on_disconnected();
                    }
                    false
                }
                Some(BleCommand::Connect) => {
                    *want_connected = true;
                    false
                }
                Some(BleCommand::SetAutoReconnect(val)) => {
                    *auto_reconnect = val;
                    false
                }
                Some(BleCommand::Shutdown) | None => {
                    let _ = input_tx.send(InputCommand::ReleaseAll);
                    true
                }
            }
        }
    }
}

async fn find_daydream_peripheral(adapter: &Adapter) -> Result<Option<Peripheral>, String> {
    let peripherals = adapter
        .peripherals()
        .await
        .map_err(|e| format!("BLE peripheral query failed: {e}"))?;
    for p in peripherals {
        if let Ok(Some(props)) = p.properties().await
            && matches_daydream_peripheral(props.local_name.as_deref(), &props.services)
        {
            return Ok(Some(p));
        }
    }
    Ok(None)
}

async fn connect_and_stream_once(
    cmd_rx: &mut tokio_mpsc::UnboundedReceiver<BleCommand>,
    input_tx: &mpsc::Sender<InputCommand>,
    status: &Arc<Mutex<Status>>,
    clock_origin: Instant,
    auto_reconnect: &mut bool,
    want_connected: &mut bool,
) -> Result<SessionOutcome, String> {
    let manager = Manager::new()
        .await
        .map_err(|e| format!("Bluetooth unavailable: {e}"))?;
    let adapters = manager
        .adapters()
        .await
        .map_err(|e| format!("Failed to query Bluetooth adapters: {e}"))?;
    let adapter = adapters
        .into_iter()
        .next()
        .ok_or_else(|| "No Bluetooth adapter found".to_string())?;

    let service_uuid = Uuid::parse_str(Daydream::SERVICE_UUID).expect("valid Daydream UUID");
    let notify_uuid = Uuid::parse_str(Daydream::NOTIFY_UUID).expect("valid notify UUID");
    let battery_char_uuid = Uuid::parse_str(BATTERY_CHAR_UUID).expect("valid battery char UUID");
    let _ = Uuid::parse_str(BATTERY_SERVICE_UUID);

    adapter
        .start_scan(ScanFilter::default())
        .await
        .map_err(|e| format!("Failed to start BLE scan: {e}"))?;

    let scan_deadline = Instant::now() + Duration::from_secs(10);
    let peripheral = loop {
        if let Some(p) = find_daydream_peripheral(&adapter).await? {
            break p;
        }
        if Instant::now() >= scan_deadline {
            let _ = adapter.stop_scan().await;
            return Err("Timed out scanning for Daydream controller".to_string());
        }
        tokio::select! {
            _ = tokio::time::sleep(Duration::from_millis(250)) => {}
            cmd = cmd_rx.recv() => {
                match cmd {
                    Some(BleCommand::Disconnect) => {
                        let _ = adapter.stop_scan().await;
                        *want_connected = false;
                        let _ = input_tx.send(InputCommand::ReleaseAll);
                        return Ok(SessionOutcome::UserDisconnected);
                    }
                    Some(BleCommand::SetAutoReconnect(val)) => {
                        *auto_reconnect = val;
                    }
                    Some(BleCommand::Connect) => {}
                    Some(BleCommand::Shutdown) | None => {
                        let _ = adapter.stop_scan().await;
                        let _ = input_tx.send(InputCommand::ReleaseAll);
                        return Ok(SessionOutcome::Shutdown);
                    }
                }
            }
        }
    };

    let _ = adapter.stop_scan().await;

    peripheral
        .connect()
        .await
        .map_err(|e| format!("Failed to connect to Daydream controller: {e}"))?;
    peripheral
        .discover_services()
        .await
        .map_err(|e| format!("Failed to discover GATT services: {e}"))?;

    let chars = peripheral.characteristics();
    let notify_char: Characteristic = chars
        .iter()
        .find(|c| c.uuid == notify_uuid || c.service_uuid == service_uuid && c.uuid == notify_uuid)
        .cloned()
        .ok_or_else(|| "Daydream sensor notification characteristic not found".to_string())?;
    let battery_char: Option<Characteristic> =
        chars.iter().find(|c| c.uuid == battery_char_uuid).cloned();

    peripheral
        .subscribe(&notify_char)
        .await
        .map_err(|e| format!("Failed to subscribe to Daydream notifications: {e}"))?;

    if let Ok(mut st) = status.lock() {
        st.on_connected("Daydream");
    }

    if let Some(ref bchar) = battery_char
        && let Ok(bytes) = peripheral.read(bchar).await
        && let Some(&lvl) = bytes.first()
        && let Ok(mut st) = status.lock()
    {
        st.update_battery(lvl);
    }

    let mut notifications = peripheral
        .notifications()
        .await
        .map_err(|e| format!("Failed to open notification stream: {e}"))?;
    let mut battery_ticker = tokio::time::interval(BATTERY_POLL_INTERVAL);
    battery_ticker.tick().await; // consume immediate tick

    loop {
        tokio::select! {
            maybe_notif = notifications.next() => {
                match maybe_notif {
                    Some(notif) => {
                        if notif.uuid == notify_uuid && notif.value.len() >= 20 {
                            let mut bytes = [0u8; 20];
                            bytes.copy_from_slice(&notif.value[..20]);
                            let t_us = clock_origin.elapsed().as_micros() as u64;
                            let _ = input_tx.send(InputCommand::Packet { bytes, t_us });
                        } else if notif.uuid == battery_char_uuid
                            && let Some(&lvl) = notif.value.first()
                            && let Ok(mut st) = status.lock()
                        {
                            st.update_battery(lvl);
                        }
                    }
                    None => {
                        let _ = input_tx.send(InputCommand::ReleaseAll);
                        let _ = peripheral.disconnect().await;
                        return Ok(SessionOutcome::ConnectionLost);
                    }
                }
            }
            _ = battery_ticker.tick() => {
                if let Some(ref bchar) = battery_char
                    && let Ok(bytes) = peripheral.read(bchar).await
                    && let Some(&lvl) = bytes.first()
                    && let Ok(mut st) = status.lock()
                {
                    st.update_battery(lvl);
                }
            }
            cmd = cmd_rx.recv() => {
                match cmd {
                    Some(BleCommand::Disconnect) => {
                        let _ = input_tx.send(InputCommand::ReleaseAll);
                        let _ = peripheral.unsubscribe(&notify_char).await;
                        let _ = peripheral.disconnect().await;
                        return Ok(SessionOutcome::UserDisconnected);
                    }
                    Some(BleCommand::SetAutoReconnect(val)) => {
                        *auto_reconnect = val;
                    }
                    Some(BleCommand::Connect) => {}
                    Some(BleCommand::Shutdown) | None => {
                        let _ = input_tx.send(InputCommand::ReleaseAll);
                        let _ = peripheral.unsubscribe(&notify_char).await;
                        let _ = peripheral.disconnect().await;
                        return Ok(SessionOutcome::Shutdown);
                    }
                }
            }
        }
    }
}
