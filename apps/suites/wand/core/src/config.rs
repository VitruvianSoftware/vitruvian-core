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

//! Versioned user configuration, settings, documented validation ranges, bindings, and radial menu slots.

use crate::bindings::{default_bindings, serde_bindings, Bindings, Platform};
use crate::radial::{RadialSlot, RADIAL_SLOT_COUNT};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// Current schema version for [`Config`].
/// Version 2 inverted `ema_smoothing` (it now means "how much smoothing") and lowered its default.
/// Version 3 added `pointing_mode`, `pointing_span_deg`, and `screen_width_px`.
/// Version 4 added `motion_glide`.
pub const CONFIG_VERSION: u32 = 4;

/// Gyroscope pointing mode (`Absolute` laser-pointer vs `Relative` mouse-like deltas).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PointingMode {
    /// Absolute ("laser pointer") mode: integrates gyro aim and emits [`crate::bindings::Action::PointTo`].
    #[default]
    Absolute,
    /// Relative ("mouse") mode: emits [`crate::bindings::Action::Move`] deltas from angular velocity.
    Relative,
}

impl PointingMode {
    /// Returns the default [`PointingMode`] for `platform`:
    /// [`PointingMode::Absolute`] on [`Platform::Desktop`] and [`PointingMode::Relative`] on
    /// [`Platform::Android`] and [`Platform::AndroidTv`].
    pub const fn default_for_platform(platform: Platform) -> Self {
        match platform {
            Platform::Desktop => Self::Absolute,
            Platform::Android | Platform::AndroidTv => Self::Relative,
        }
    }
}

/// Documented `(min, max, default)` range entry for an `f32` setting.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SettingRangeF32 {
    /// Setting field identifier in `[settings]`.
    pub key: &'static str,
    /// Minimum valid value.
    pub min: f32,
    /// Maximum valid value.
    pub max: f32,
    /// Default value (used when clamping `NaN`).
    pub default: f32,
}

impl SettingRangeF32 {
    /// Clamps `value` to `[self.min, self.max]`, replacing `NaN` with `self.default`.
    #[inline]
    pub fn clamp(self, value: f32) -> f32 {
        if value.is_nan() {
            self.default
        } else {
            value.clamp(self.min, self.max)
        }
    }
}

/// Documented `(min, max, default)` range entry for a `u64` setting.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SettingRangeU64 {
    /// Setting field identifier in `[settings]`.
    pub key: &'static str,
    /// Minimum valid value.
    pub min: u64,
    /// Maximum valid value.
    pub max: u64,
    /// Default value.
    pub default: u64,
}

impl SettingRangeU64 {
    /// Clamps `value` to `[self.min, self.max]`.
    #[inline]
    pub fn clamp(self, value: u64) -> u64 {
        value.clamp(self.min, self.max)
    }
}

pub const RANGE_TOUCH_SENSITIVITY: SettingRangeF32 = SettingRangeF32 {
    key: "touch_sensitivity",
    min: 50.0,
    max: 1200.0,
    default: 400.0,
};
pub const RANGE_GYRO_X_SPEED: SettingRangeF32 = SettingRangeF32 {
    key: "gyro_x_speed",
    min: 1.0,
    max: 60.0,
    default: 18.0,
};
pub const RANGE_GYRO_Y_SPEED: SettingRangeF32 = SettingRangeF32 {
    key: "gyro_y_speed",
    min: 1.0,
    max: 60.0,
    default: 18.0,
};
pub const RANGE_GYRO_DEADZONE: SettingRangeF32 = SettingRangeF32 {
    key: "gyro_deadzone",
    min: 0.0,
    max: 0.5,
    default: 0.03,
};
pub const RANGE_TOUCH_DEADZONE: SettingRangeF32 = SettingRangeF32 {
    key: "touch_deadzone",
    min: 0.0,
    max: 0.2,
    default: 0.005,
};
pub const RANGE_ACCELERATION_CURVE: SettingRangeF32 = SettingRangeF32 {
    key: "acceleration_curve",
    min: 1.0,
    max: 3.0,
    default: 1.0,
};
pub const RANGE_EMA_SMOOTHING: SettingRangeF32 = SettingRangeF32 {
    key: "ema_smoothing",
    min: 0.0,
    max: 0.95,
    // How much smoothing, not how much response (inverted before config version 2).
    default: 0.3,
};
pub const RANGE_SCROLL_STRENGTH: SettingRangeF32 = SettingRangeF32 {
    key: "scroll_strength",
    min: 0.1,
    max: 5.0,
    default: 1.0,
};
pub const RANGE_RADIAL_DEAD_RADIUS: SettingRangeF32 = SettingRangeF32 {
    key: "radial_dead_radius",
    min: 0.0,
    max: 100.0,
    default: 15.0,
};
pub const RANGE_OVERLAY_CURSOR_SIZE: SettingRangeF32 = SettingRangeF32 {
    key: "overlay_cursor_size",
    min: 8.0,
    max: 128.0,
    default: 24.0,
};
pub const RANGE_POINTING_SPAN_DEG: SettingRangeF32 = SettingRangeF32 {
    key: "pointing_span_deg",
    min: 15.0,
    max: 150.0,
    default: 50.0,
};

pub const RANGE_LONG_PRESS_MS: SettingRangeU64 = SettingRangeU64 {
    key: "long_press_ms",
    min: 100,
    max: 5000,
    default: 500,
};
pub const RANGE_DOUBLE_PRESS_MS: SettingRangeU64 = SettingRangeU64 {
    key: "double_press_ms",
    min: 50,
    max: 2000,
    default: 300,
};
pub const RANGE_SCREEN_WIDTH_PX: SettingRangeU64 = SettingRangeU64 {
    key: "screen_width_px",
    min: 640,
    max: 7680,
    default: 1920,
};

/// Single authoritative table of `f32` setting validation ranges.
pub const SETTING_RANGES_F32: [SettingRangeF32; 11] = [
    RANGE_TOUCH_SENSITIVITY,
    RANGE_GYRO_X_SPEED,
    RANGE_GYRO_Y_SPEED,
    RANGE_GYRO_DEADZONE,
    RANGE_TOUCH_DEADZONE,
    RANGE_ACCELERATION_CURVE,
    RANGE_EMA_SMOOTHING,
    RANGE_SCROLL_STRENGTH,
    RANGE_RADIAL_DEAD_RADIUS,
    RANGE_OVERLAY_CURSOR_SIZE,
    RANGE_POINTING_SPAN_DEG,
];

/// Single authoritative table of `u64` setting validation ranges.
pub const SETTING_RANGES_U64: [SettingRangeU64; 3] = [
    RANGE_LONG_PRESS_MS,
    RANGE_DOUBLE_PRESS_MS,
    RANGE_SCREEN_WIDTH_PX,
];

/// User-adjustable pointer, scroll, gesture, and UI settings (spec §2).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    /// Gyroscope pointing mode (`Absolute` laser-pointer vs `Relative` mouse-like deltas).
    pub pointing_mode: PointingMode,
    /// Horizontal angle in degrees that sweeps the full screen width in `Absolute` mode.
    pub pointing_span_deg: f32,
    /// Screen width in pixels used on Linux to convert `PointTo` deltas into uinput relative events.
    pub screen_width_px: u64,
    /// Linearly interpolate cursor positions between BLE packet updates in `Absolute` mode (Desktop).
    pub motion_glide: bool,
    /// Touchpad pointer sensitivity multiplier.
    pub touch_sensitivity: f32,
    /// Horizontal gyroscope speed multiplier.
    pub gyro_x_speed: f32,
    /// Vertical gyroscope speed multiplier.
    pub gyro_y_speed: f32,
    /// Gyroscope tremor deadzone in rad/s.
    pub gyro_deadzone: f32,
    /// Touchpad movement deadzone in normalized `0.0..=1.0` coordinates.
    pub touch_deadzone: f32,
    /// Non-linear pointer acceleration exponent (`1.0` = linear).
    pub acceleration_curve: f32,
    /// Exponential moving average smoothing factor `α` in `(0.0, 1.0]` (`1.0` = unsmoothed).
    pub ema_smoothing: f32,
    /// Invert scroll direction when `true`.
    pub reverse_scroll: bool,
    /// Scroll speed multiplier.
    pub scroll_strength: f32,
    /// Enable horizontal touchpad scrolling in gyro mode.
    pub horizontal_scroll: bool,
    /// Enable touchpad tap-to-click while in touchpad pointer mode.
    pub tap_in_touch_mode: bool,
    /// Enable touchpad tap-to-click while in gyro pointer mode.
    pub tap_in_gyro_mode: bool,
    /// Automatically reconnect to the last paired controller.
    pub auto_reconnect: bool,
    /// Long-press threshold in milliseconds (default `500`).
    pub long_press_ms: u64,
    /// Double-press maximum gap in milliseconds (default `300`).
    pub double_press_ms: u64,
    /// Dead-centre radius for the 8-slot radial menu.
    pub radial_dead_radius: f32,
    /// Show the Android accessibility overlay cursor.
    pub overlay_cursor: bool,
    /// Size of the Android accessibility overlay cursor in dp.
    pub overlay_cursor_size: f32,
    /// Preserved unknown keys inside `[settings]` for forward compatibility.
    #[serde(flatten)]
    pub extra: BTreeMap<String, serde_json::Value>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            pointing_mode: PointingMode::Absolute,
            pointing_span_deg: RANGE_POINTING_SPAN_DEG.default,
            screen_width_px: RANGE_SCREEN_WIDTH_PX.default,
            motion_glide: true,
            touch_sensitivity: RANGE_TOUCH_SENSITIVITY.default,
            gyro_x_speed: RANGE_GYRO_X_SPEED.default,
            gyro_y_speed: RANGE_GYRO_Y_SPEED.default,
            gyro_deadzone: RANGE_GYRO_DEADZONE.default,
            touch_deadzone: RANGE_TOUCH_DEADZONE.default,
            acceleration_curve: RANGE_ACCELERATION_CURVE.default,
            ema_smoothing: RANGE_EMA_SMOOTHING.default,
            reverse_scroll: false,
            scroll_strength: RANGE_SCROLL_STRENGTH.default,
            horizontal_scroll: false,
            tap_in_touch_mode: true,
            tap_in_gyro_mode: true,
            auto_reconnect: true,
            long_press_ms: RANGE_LONG_PRESS_MS.default,
            double_press_ms: RANGE_DOUBLE_PRESS_MS.default,
            radial_dead_radius: RANGE_RADIAL_DEAD_RADIUS.default,
            overlay_cursor: true,
            overlay_cursor_size: RANGE_OVERLAY_CURSOR_SIZE.default,
            extra: BTreeMap::new(),
        }
    }
}

impl Settings {
    /// Clamps all numeric fields to their documented ranges in [`SETTING_RANGES_F32`] and
    /// [`SETTING_RANGES_U64`], replacing any `NaN` with the setting's default value.
    pub fn sanitize(&mut self) {
        self.pointing_span_deg = RANGE_POINTING_SPAN_DEG.clamp(self.pointing_span_deg);
        self.screen_width_px = RANGE_SCREEN_WIDTH_PX.clamp(self.screen_width_px);
        self.touch_sensitivity = RANGE_TOUCH_SENSITIVITY.clamp(self.touch_sensitivity);
        self.gyro_x_speed = RANGE_GYRO_X_SPEED.clamp(self.gyro_x_speed);
        self.gyro_y_speed = RANGE_GYRO_Y_SPEED.clamp(self.gyro_y_speed);
        self.gyro_deadzone = RANGE_GYRO_DEADZONE.clamp(self.gyro_deadzone);
        self.touch_deadzone = RANGE_TOUCH_DEADZONE.clamp(self.touch_deadzone);
        self.acceleration_curve = RANGE_ACCELERATION_CURVE.clamp(self.acceleration_curve);
        self.ema_smoothing = RANGE_EMA_SMOOTHING.clamp(self.ema_smoothing);
        self.scroll_strength = RANGE_SCROLL_STRENGTH.clamp(self.scroll_strength);
        self.radial_dead_radius = RANGE_RADIAL_DEAD_RADIUS.clamp(self.radial_dead_radius);
        self.overlay_cursor_size = RANGE_OVERLAY_CURSOR_SIZE.clamp(self.overlay_cursor_size);
        self.long_press_ms = RANGE_LONG_PRESS_MS.clamp(self.long_press_ms);
        self.double_press_ms = RANGE_DOUBLE_PRESS_MS.clamp(self.double_press_ms);
    }

    /// Returns a sanitized copy of `self`.
    pub fn sanitized(mut self) -> Self {
        self.sanitize();
        self
    }
}

/// Top-level serializable configuration for Wand.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Config {
    /// Schema version number.
    pub version: u32,
    /// Target platform used for default bindings.
    pub platform: Platform,
    /// Pointer, scroll, and gesture settings.
    pub settings: Settings,
    /// Per-button short/long/double bindings.
    #[serde(with = "serde_bindings")]
    pub bindings: Bindings,
    /// 8-slot radial menu configuration.
    pub radial_slots: Vec<RadialSlot>,
    /// Preserved unknown fields for forward compatibility across schema revisions.
    #[serde(flatten)]
    pub extra: BTreeMap<String, serde_json::Value>,
}

impl<'de> Deserialize<'de> for Config {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(default)]
        struct ConfigWire {
            version: u32,
            platform: Platform,
            settings: serde_json::Value,
            #[serde(with = "serde_bindings")]
            bindings: Bindings,
            radial_slots: Vec<RadialSlot>,
            #[serde(flatten)]
            extra: BTreeMap<String, serde_json::Value>,
        }

        impl Default for ConfigWire {
            fn default() -> Self {
                let def = Config::default();
                Self {
                    version: def.version,
                    platform: def.platform,
                    settings: serde_json::Value::Null,
                    bindings: def.bindings,
                    radial_slots: def.radial_slots,
                    extra: def.extra,
                }
            }
        }

        let wire = ConfigWire::deserialize(deserializer)?;
        let has_pointing_mode = wire
            .settings
            .as_object()
            .is_some_and(|m| m.contains_key("pointing_mode"));
        let mut settings = if wire.settings.is_null() {
            Settings::default()
        } else {
            serde_json::from_value::<Settings>(wire.settings).map_err(serde::de::Error::custom)?
        };
        if !has_pointing_mode {
            settings.pointing_mode = PointingMode::default_for_platform(wire.platform);
        }
        Ok(Self {
            version: wire.version,
            platform: wire.platform,
            settings,
            bindings: wire.bindings,
            radial_slots: wire.radial_slots,
            extra: wire.extra,
        })
    }
}

impl Default for Config {
    fn default() -> Self {
        Self::for_platform(Platform::Desktop)
    }
}

impl Config {
    /// Returns a default [`Config`] tailored to `platform`.
    pub fn for_platform(platform: Platform) -> Self {
        Self {
            version: CONFIG_VERSION,
            platform,
            settings: Settings {
                pointing_mode: PointingMode::default_for_platform(platform),
                ..Settings::default()
            },
            bindings: default_bindings(platform),
            radial_slots: vec![RadialSlot::default(); RADIAL_SLOT_COUNT],
            extra: BTreeMap::new(),
        }
    }

    /// Clamps all settings in `self.settings` to their documented ranges.
    pub fn sanitize(&mut self) {
        if self.version < 2 {
            // Old files stored the response weight under this key; reading it as a smoothing
            // amount would invert the user's setting, so start them on the new default.
            self.settings.ema_smoothing = RANGE_EMA_SMOOTHING.default;
        }
        self.version = CONFIG_VERSION;
        self.settings.sanitize();
    }

    /// Returns a sanitized copy of `self`.
    pub fn sanitized(mut self) -> Self {
        self.sanitize();
        self
    }

    /// Resets `settings`, `bindings`, and `radial_slots` back to the defaults for `self.platform`.
    pub fn reset_to_defaults(&mut self) {
        self.version = CONFIG_VERSION;
        self.settings = Settings {
            pointing_mode: PointingMode::default_for_platform(self.platform),
            ..Settings::default()
        };
        self.bindings = default_bindings(self.platform);
        self.radial_slots = vec![RadialSlot::default(); RADIAL_SLOT_COUNT];
    }
}
