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

//! `vitruvian-wand-core`: deterministic, I/O-free air-mouse engine for the Google Daydream controller.
//!
//! Feeds `(20-byte BLE packet, timestamp_us)` into [`engine::Engine`] and receives
//! `Vec<bindings::Action>` with no threads, clocks, Bluetooth, or operating system calls.

pub mod bindings;
pub mod buttons;
pub mod calibration;
pub mod config;
pub mod controller;
pub mod engine;
pub mod pointer;
pub mod protocol;
pub mod radial;
pub mod replay;

pub use bindings::{
    default_bindings, Action, Binding, Bindings, BrightnessAction, Button, Direction, KeyChord,
    MediaAction, NavAction, Platform, Press, SystemAction, Trigger, TriggerMode, VolumeAction,
};
pub use calibration::{CalibrationError, TooMuchMotion};
pub use config::{
    Config, PointingMode, SettingRangeF32, SettingRangeU64, Settings, CONFIG_VERSION,
    RANGE_ACCELERATION_CURVE, RANGE_DOUBLE_PRESS_MS, RANGE_EMA_SMOOTHING, RANGE_GYRO_DEADZONE,
    RANGE_GYRO_X_SPEED, RANGE_GYRO_Y_SPEED, RANGE_LONG_PRESS_MS, RANGE_OVERLAY_CURSOR_SIZE,
    RANGE_POINTING_SPAN_DEG, RANGE_RADIAL_DEAD_RADIUS, RANGE_SCREEN_WIDTH_PX,
    RANGE_SCROLL_STRENGTH, RANGE_TOUCH_DEADZONE, RANGE_TOUCH_SENSITIVITY, SETTING_RANGES_F32,
    SETTING_RANGES_U64,
};
pub use controller::{Controller, Daydream};
pub use engine::{battery_low, Engine, LOW_BATTERY_THRESHOLD_PERCENT};
pub use pointer::{PointerEngine, PointerMode};
pub use protocol::daydream::{Sample, Vec3};
pub use radial::{slot_for, RadialSlot, RADIAL_SLOT_COUNT};
pub use replay::{ReplayError, ReplayRecord};
