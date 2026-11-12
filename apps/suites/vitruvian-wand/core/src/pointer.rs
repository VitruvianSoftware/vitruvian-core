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

//! Touchpad and gyroscope pointer motion engine.

use crate::bindings::Action;
use crate::config::{PointingMode, Settings, RANGE_POINTING_SPAN_DEG};
use crate::protocol::daydream::{Sample, Vec3};
use serde::{Deserialize, Serialize};

/// Active pointer control mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PointerMode {
    /// Swipe on the touchpad to move the cursor.
    #[default]
    Touch,
    /// Wave the controller in the air to move the cursor.
    Gyro,
}

/// Applies the non-linear acceleration curve `sign(v) * |v|^curve`.
#[inline]
pub fn apply_accel_curve(v: f32, curve: f32) -> f32 {
    if v == 0.0 {
        0.0
    } else if (curve - 1.0).abs() <= f32::EPSILON {
        v
    } else {
        v.signum() * v.abs().powf(curve)
    }
}

/// Stateful pointer motion processor supporting touch mode and gyro mode.
#[derive(Debug, Clone, Default)]
pub struct PointerEngine {
    last_touch: Option<(f32, f32)>,
    ema_dx: f32,
    ema_dy: f32,
    last_gyro_t_us: Option<u64>,
    yaw_aim: f32,
    pitch_aim: f32,
    ema_x: f32,
    ema_y: f32,
    last_point: (f32, f32),
}

/// The packet interval the gyro speed settings are calibrated for (60 Hz).
///
/// Real controllers deliver packets irregularly: a 2026-11-08 Daydream recording on macOS
/// averaged 38 packets/s with gaps up to 180 ms. Gyro readings are rates (rad/s), so each
/// packet's motion is scaled by its real interval relative to this nominal one. Without that,
/// every late or dropped packet silently loses the rotation that happened in the gap, and the
/// pointer travels less than the hand.
pub const NOMINAL_GYRO_INTERVAL_US: u64 = 16_667;

/// Longest gap (100 ms) credited to one packet, so a reconnect or stall doesn't fling the pointer.
pub const MAX_GYRO_INTERVAL_US: u64 = 100_000;

impl PointerEngine {
    /// Creates a new [`PointerEngine`].
    pub fn new() -> Self {
        Self::default()
    }

    /// Resets transient touch-tracking, EMA smoothing, and absolute gyro aim state.
    pub fn reset(&mut self) {
        self.last_touch = None;
        self.ema_dx = 0.0;
        self.ema_dy = 0.0;
        self.recenter();
    }

    /// Resets the gyroscope absolute aim and smoothed position back to the screen centre `(0, 0)`.
    pub fn recenter(&mut self) {
        self.yaw_aim = 0.0;
        self.pitch_aim = 0.0;
        self.ema_x = 0.0;
        self.ema_y = 0.0;
        self.last_point = (0.0, 0.0);
        self.last_gyro_t_us = None;
    }

    /// Returns the integrated `(yaw_aim, pitch_aim)` in radians for [`PointingMode::Absolute`].
    pub const fn aim(&self) -> (f32, f32) {
        (self.yaw_aim, self.pitch_aim)
    }

    /// Returns the last emitted `(x, y)` coordinates in screen-width units for [`PointingMode::Absolute`].
    pub const fn last_point(&self) -> (f32, f32) {
        self.last_point
    }

    /// Like [`PointerEngine::update`], but scales gyro motion by the real time since the previous
    /// packet (see [`NOMINAL_GYRO_INTERVAL_US`]). The engine calls this for every packet.
    pub fn update_at(
        &mut self,
        sample: &Sample,
        mode: PointerMode,
        settings: &Settings,
        gyro_bias: Vec3,
        t_us: u64,
    ) -> Option<Action> {
        match mode {
            PointerMode::Touch => {
                self.last_gyro_t_us = None;
                self.update_touch(sample, settings)
            }
            PointerMode::Gyro => {
                let interval_us = match self.last_gyro_t_us.replace(t_us) {
                    Some(prev) => t_us.saturating_sub(prev).min(MAX_GYRO_INTERVAL_US),
                    None => NOMINAL_GYRO_INTERVAL_US,
                };
                self.update_gyro_interval(sample, settings, gyro_bias, interval_us)
            }
        }
    }

    /// Processes a single [`Sample`] in the specified [`PointerMode`] and returns `Some(Action::Move)`
    /// or `Some(Action::PointTo)` when pointer motion is produced.
    pub fn update(
        &mut self,
        sample: &Sample,
        mode: PointerMode,
        settings: &Settings,
        gyro_bias: Vec3,
    ) -> Option<Action> {
        match mode {
            PointerMode::Touch => self.update_touch(sample, settings),
            PointerMode::Gyro => self.update_gyro(sample, settings, gyro_bias),
        }
    }

    /// Computes touch-mode pointer movement:
    /// - Drops the first sample after touch-down to avoid cursor jumps.
    /// - Applies `settings.touch_deadzone` to the raw touch delta.
    /// - Multiplies by `settings.touch_sensitivity`.
    pub fn update_touch(&mut self, sample: &Sample, settings: &Settings) -> Option<Action> {
        if !sample.touching {
            self.last_touch = None;
            return None;
        }

        let Some((prev_x, prev_y)) = self.last_touch.replace((sample.touch_x, sample.touch_y))
        else {
            // First sample after touch-down: anchor position and emit no movement.
            return None;
        };

        let raw_dx = sample.touch_x - prev_x;
        let raw_dy = sample.touch_y - prev_y;
        let mag = (raw_dx * raw_dx + raw_dy * raw_dy).sqrt();
        if mag <= settings.touch_deadzone {
            return None;
        }

        let dx = raw_dx * settings.touch_sensitivity;
        let dy = raw_dy * settings.touch_sensitivity;
        if dx == 0.0 && dy == 0.0 {
            None
        } else {
            Some(Action::Move { dx, dy })
        }
    }

    /// Computes gyro-mode pointer movement:
    /// - Subtracts `gyro_bias` from `sample.gyro`.
    /// - Suppresses tremors within `settings.gyro_deadzone`.
    /// - In [`PointingMode::Relative`], applies `sign(v) * |v|^curve` acceleration curve, scales by
    ///   `gyro_x_speed` / `gyro_y_speed`, and smooths the velocity with EMA (`alpha = 1 - ema_smoothing`).
    /// - In [`PointingMode::Absolute`], integrates `(yaw_aim, pitch_aim)` in radians over the packet
    ///   interval without an acceleration curve, maps to screen-width units via `pointing_span_deg`,
    ///   and smooths the output position with EMA (`alpha = 1 - ema_smoothing`).
    ///
    /// Assumes one nominal packet interval; see [`PointerEngine::update_at`].
    pub fn update_gyro(
        &mut self,
        sample: &Sample,
        settings: &Settings,
        gyro_bias: Vec3,
    ) -> Option<Action> {
        self.update_gyro_interval(sample, settings, gyro_bias, NOMINAL_GYRO_INTERVAL_US)
    }

    fn update_gyro_interval(
        &mut self,
        sample: &Sample,
        settings: &Settings,
        gyro_bias: Vec3,
        interval_us: u64,
    ) -> Option<Action> {
        // Controller axes, measured on a real Daydream (2026-11-08 recording): gyro.y is yaw
        // (turning left/right), gyro.x is pitch (tilting up/down), gyro.z is roll (wrist twist,
        // ignored). Right-hand rule with y up and the controller pointing along -z: turning left
        // and tilting up are positive. Screen x grows rightwards and screen y grows downwards,
        // so both are negated.
        let gx = -(sample.gyro.y - gyro_bias.y);
        let gy = -(sample.gyro.x - gyro_bias.x);
        let mag = (gx * gx + gy * gy).sqrt();

        match settings.pointing_mode {
            PointingMode::Relative => {
                if mag <= settings.gyro_deadzone {
                    self.ema_dx = 0.0;
                    self.ema_dy = 0.0;
                    return None;
                }

                let interval_scale = interval_us as f32 / NOMINAL_GYRO_INTERVAL_US as f32;
                let curved_x = apply_accel_curve(gx, settings.acceleration_curve);
                let curved_y = apply_accel_curve(gy, settings.acceleration_curve);

                let target_dx = curved_x * settings.gyro_x_speed * interval_scale;
                let target_dy = curved_y * settings.gyro_y_speed * interval_scale;

                let alpha = (1.0 - settings.ema_smoothing).clamp(0.05, 1.0);
                let dx = alpha * target_dx + (1.0 - alpha) * self.ema_dx;
                let dy = alpha * target_dy + (1.0 - alpha) * self.ema_dy;
                self.ema_dx = dx;
                self.ema_dy = dy;

                if dx == 0.0 && dy == 0.0 {
                    None
                } else {
                    Some(Action::Move { dx, dy })
                }
            }
            PointingMode::Absolute => {
                if mag <= settings.gyro_deadzone {
                    return None;
                }

                // Integrate aim in radians: yaw_aim has screen-x sign (dx = -yaw, so turning left
                // gives negative yaw_aim and negative x); pitch_aim is positive when tilting up
                // (pitch = gyro.x), so y = -pitch_aim / span_rad is negative when tilting up.
                let dt_s = interval_us as f32 / 1_000_000.0;
                let yaw_rate = gx;
                let pitch_rate = sample.gyro.x - gyro_bias.x;
                self.yaw_aim += yaw_rate * dt_s;
                self.pitch_aim += pitch_rate * dt_s;

                let span_deg = RANGE_POINTING_SPAN_DEG.clamp(settings.pointing_span_deg);
                let span_rad = span_deg.to_radians();
                let target_x = self.yaw_aim / span_rad;
                let target_y = -self.pitch_aim / span_rad;

                let alpha = (1.0 - settings.ema_smoothing).clamp(0.05, 1.0);
                let x = alpha * target_x + (1.0 - alpha) * self.ema_x;
                let y = alpha * target_y + (1.0 - alpha) * self.ema_y;
                self.ema_x = x;
                self.ema_y = y;

                if !x.is_finite() || !y.is_finite() || (x, y) == self.last_point {
                    None
                } else {
                    self.last_point = (x, y);
                    Some(Action::PointTo { x, y })
                }
            }
        }
    }
}
