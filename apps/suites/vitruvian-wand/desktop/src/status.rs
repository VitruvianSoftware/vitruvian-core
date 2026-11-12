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

//! Shared [`Status`] between BLE, input, tray, and UI threads, including
//! once-per-connection low-battery (`< 15%`) alert tracking.

use vitruvian_wand_core::{Sample, battery_low};

/// Current BLE connection lifecycle state displayed in the header status pill.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub enum ConnectionState {
    /// Not connected and not scanning.
    #[default]
    Disconnected,
    /// Scanning for or connecting to a Daydream controller.
    Scanning,
    /// Connected and subscribed to sensor notifications.
    Connected,
    /// Connection or adapter error.
    Error(String),
}

impl ConnectionState {
    /// Returns `true` when currently connected.
    pub const fn is_connected(&self) -> bool {
        matches!(self, Self::Connected)
    }

    /// Returns `true` when scanning or connecting.
    pub const fn is_scanning(&self) -> bool {
        matches!(self, Self::Scanning)
    }
}

/// Shared runtime state read by the 30 Hz UI loop and written by the BLE and input threads.
#[derive(Debug, Clone)]
pub struct Status {
    /// BLE connection state.
    pub connection: ConnectionState,
    /// Connected controller display name (e.g. `"Daydream"`).
    pub device_name: String,
    /// Latest battery percentage (`0..=100`), if reported by `0x180F` / `0x2A19`.
    pub battery_percent: Option<u8>,
    /// Whether the low-battery (`< 15%`) UI banner should currently be shown.
    pub low_battery_alert_active: bool,
    /// Whether the low-battery alert has already fired during the current connection.
    pub low_battery_notified_this_connection: bool,
    /// Whether a pending tray tooltip notification should be pushed on the main thread.
    pub pending_low_battery_tray_notice: Option<u8>,
    /// Most recent decoded sensor packet sample.
    pub last_sample: Option<Sample>,
    /// Whether gyro pointer mode is active (`false` = touchpad mode).
    pub gyro_mode: bool,
    /// Whether live visualizer test mode is active (suppresses OS injection).
    pub test_mode: bool,
    /// Whether stationary gyroscope calibration is currently collecting samples.
    pub calibrating: bool,
    /// Error message from the most recent calibration attempt, if it failed.
    pub calibration_error: Option<String>,
    /// Whether host input injection permission (macOS Accessibility / Linux `/dev/uinput`) is granted.
    pub permission_ok: bool,
    /// Human-readable status or remediation message for host permissions.
    pub permission_message: String,
    /// Whether the radial menu overlay window should currently be visible.
    pub radial_open: bool,
    /// Accumulated pointer delta `(dx, dy)` from the radial menu origin while held.
    pub radial_offset: (f32, f32),
    /// Currently highlighted radial slot (`0..=7`), or `None` when inside the deadzone.
    pub radial_selected_slot: Option<u8>,
}

impl Default for Status {
    fn default() -> Self {
        Self {
            connection: ConnectionState::Disconnected,
            device_name: "Daydream".to_string(),
            battery_percent: None,
            low_battery_alert_active: false,
            low_battery_notified_this_connection: false,
            pending_low_battery_tray_notice: None,
            last_sample: None,
            gyro_mode: false,
            test_mode: false,
            calibrating: false,
            calibration_error: None,
            permission_ok: true,
            permission_message: String::new(),
            radial_open: false,
            radial_offset: (0.0, 0.0),
            radial_selected_slot: None,
        }
    }
}

impl Status {
    /// Creates a new default [`Status`].
    pub fn new() -> Self {
        Self::default()
    }

    /// Marks the controller as connected and resets per-connection low-battery state.
    pub fn on_connected(&mut self, device_name: impl Into<String>) {
        self.connection = ConnectionState::Connected;
        self.device_name = device_name.into();
        self.low_battery_alert_active = false;
        self.low_battery_notified_this_connection = false;
        self.pending_low_battery_tray_notice = None;
    }

    /// Marks the controller as disconnected and clears transient session state.
    pub fn on_disconnected(&mut self) {
        self.connection = ConnectionState::Disconnected;
        self.battery_percent = None;
        self.low_battery_alert_active = false;
        self.low_battery_notified_this_connection = false;
        self.pending_low_battery_tray_notice = None;
        self.radial_open = false;
        self.radial_offset = (0.0, 0.0);
        self.radial_selected_slot = None;
    }

    /// Updates the battery level (`0..=100` %) and triggers the low-battery alert
    /// (`< 15%`) at most once per connection.
    ///
    /// Returns `true` on the exact transition where the low-battery alert fires for
    /// this connection (so the caller can update the tray tooltip and display the banner).
    pub fn update_battery(&mut self, level: u8) -> bool {
        let clamped = level.min(100);
        self.battery_percent = Some(clamped);
        if battery_low(clamped) && !self.low_battery_notified_this_connection {
            self.low_battery_notified_this_connection = true;
            self.low_battery_alert_active = true;
            self.pending_low_battery_tray_notice = Some(clamped);
            true
        } else {
            false
        }
    }

    /// Returns the 4-level battery icon index (`0..=3`) for a given percentage.
    /// - `0`: 0..25%
    /// - `1`: 25..50%
    /// - `2`: 50..75%
    /// - `3`: 75..=100%
    pub const fn battery_level_bars(percent: u8) -> u8 {
        if percent < 25 {
            1
        } else if percent < 50 {
            2
        } else if percent < 75 {
            3
        } else {
            4
        }
    }
}
