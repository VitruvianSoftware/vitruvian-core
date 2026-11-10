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

//! Deterministic, I/O-free air-mouse engine combining decoding, calibration,
//! pointer motion, button state machines, radial menu selection, and gyro-mode touchpad gestures.

use crate::bindings::{Action, Button, Direction, Platform, Press};
use crate::buttons::ButtonMachine;
use crate::calibration::{
    CalibrationError, Calibrator, DEFAULT_CALIBRATION_SAMPLES, DEFAULT_MOTION_THRESHOLD,
};
use crate::config::Config;
use crate::pointer::{PointerEngine, PointerMode};
use crate::protocol::daydream::{self, Sample, Vec3};
use crate::radial::slot_for;

/// Low-battery alert threshold in percent (`< 15%`).
pub const LOW_BATTERY_THRESHOLD_PERCENT: u8 = 15;

/// Minimum normalized touchpad travel in gyro mode on Android TV to emit a D-pad focus step.
const TV_SWIPE_THRESHOLD: f32 = 0.20;

/// Returns `true` when `level` (in `0..=100` percent) is below the 15% low-battery threshold.
#[inline]
pub const fn battery_low(level: u8) -> bool {
    level < LOW_BATTERY_THRESHOLD_PERCENT
}

#[derive(Debug, Clone, Default)]
struct GyroTouchpadState {
    last_pos: Option<(f32, f32)>,
    swipe_anchor: Option<(f32, f32)>,
    swipe_emitted: bool,
}

impl GyroTouchpadState {
    fn reset(&mut self) {
        self.last_pos = None;
        self.swipe_anchor = None;
        self.swipe_emitted = false;
    }
}

#[derive(Debug, Clone)]
struct ActiveRadial {
    button: Button,
    press: Press,
    dx: f32,
    dy: f32,
}

/// Deterministic, I/O-free Wand controller engine.
#[derive(Debug, Clone)]
pub struct Engine {
    config: Config,
    platform: Platform,
    mode: PointerMode,
    test_mode: bool,
    last_sample: Option<Sample>,
    gyro_bias: Vec3,
    calibrator: Option<Calibrator>,
    last_calibration_error: Option<CalibrationError>,
    pointer: PointerEngine,
    buttons: ButtonMachine,
    gyro_touch: GyroTouchpadState,
    radial: Option<ActiveRadial>,
    pending_actions: Vec<Action>,
}

impl Engine {
    /// Creates a new [`Engine`] with `config` and target `platform`.
    pub fn new(mut config: Config, platform: Platform) -> Self {
        config.platform = platform;
        config.sanitize();
        Self {
            config,
            platform,
            mode: PointerMode::Touch,
            test_mode: false,
            last_sample: None,
            gyro_bias: Vec3::default(),
            calibrator: None,
            last_calibration_error: None,
            pointer: PointerEngine::new(),
            buttons: ButtonMachine::new(),
            gyro_touch: GyroTouchpadState::default(),
            radial: None,
            pending_actions: Vec::new(),
        }
    }

    /// Returns a reference to the active [`Config`].
    pub fn config(&self) -> &Config {
        &self.config
    }

    /// Replaces the active [`Config`], clamping all settings to their documented ranges.
    ///
    /// Any held or toggled binding is released first, using the *old* bindings, so changing a
    /// binding mid-drag cannot strand a MouseDown. The release actions are queued and returned by
    /// the next [`Engine::feed`] or [`Engine::tick`].
    pub fn set_config(&mut self, mut config: Config) {
        let released = self.release_all();
        self.pending_actions.extend(released);
        config.platform = self.platform;
        config.sanitize();
        self.config = config;
    }

    /// Returns the active [`Platform`].
    pub const fn platform(&self) -> Platform {
        self.platform
    }

    /// Returns the current [`PointerMode`] (`Touch` or `Gyro`).
    pub const fn pointer_mode(&self) -> PointerMode {
        self.mode
    }

    /// Returns `true` if gyro pointer mode is currently active.
    pub const fn gyro_mode(&self) -> bool {
        matches!(self.mode, PointerMode::Gyro)
    }

    /// Explicitly sets whether gyro pointer mode is active.
    pub fn set_gyro_mode(&mut self, enabled: bool) {
        let next = if enabled {
            PointerMode::Gyro
        } else {
            PointerMode::Touch
        };
        if self.mode != next {
            self.mode = next;
            self.pointer.reset();
            self.gyro_touch.reset();
        }
    }

    /// Recenters the gyroscope absolute aim and smoothed position back to `(0, 0)`.
    pub fn recenter(&mut self) {
        self.pointer.recenter();
    }

    /// Returns the integrated `(yaw_aim, pitch_aim)` in radians for [`crate::config::PointingMode::Absolute`].
    pub const fn pointer_aim(&self) -> (f32, f32) {
        self.pointer.aim()
    }

    /// Releases every active [`crate::bindings::TriggerMode::Hold`] and
    /// [`crate::bindings::TriggerMode::Toggle`] binding (e.g. returning [`Action::MouseUp`] for a
    /// held click), closes any open radial menu without running a slot, and resets button and
    /// pointer state machines.
    pub fn release_all(&mut self) -> Vec<Action> {
        let mut out = std::mem::take(&mut self.pending_actions);
        out.extend(self.buttons.release_all(&self.config.bindings));
        // Forget the last packet: `tick` replays it between packets, and a stale "button down"
        // sample would re-press the button we just released (e.g. while disconnected).
        self.last_sample = None;
        self.radial = None;
        self.pointer.reset();
        self.gyro_touch.reset();
        out
    }

    /// Enables or disables live visualizer test mode.
    ///
    /// When `enabled` is `true`, [`Engine::release_all`] is invoked so any active holds or
    /// toggles are released and any open radial menu is closed without running a slot;
    /// [`Engine::feed`] emits no output [`Action`]s while in test mode, but
    /// [`Engine::last_sample`] continues to update on every packet.
    pub fn set_test_mode(&mut self, enabled: bool) {
        self.test_mode = enabled;
        if enabled {
            let released = self.release_all();
            self.pending_actions.extend(released);
        }
    }

    /// Returns `true` if the engine is currently in test mode.
    pub const fn is_test_mode(&self) -> bool {
        self.test_mode
    }

    /// Returns `true` if a radial menu hold is currently active.
    pub const fn is_radial_active(&self) -> bool {
        self.radial.is_some()
    }

    /// Returns the most recently decoded [`Sample`], if at least one packet has been fed.
    pub const fn last_sample(&self) -> Option<&Sample> {
        self.last_sample.as_ref()
    }

    /// Starts stationary gyroscope bias calibration over the next [`DEFAULT_CALIBRATION_SAMPLES`] packets.
    pub fn recalibrate(&mut self) {
        self.recalibrate_with(DEFAULT_CALIBRATION_SAMPLES, DEFAULT_MOTION_THRESHOLD);
    }

    /// Starts stationary gyroscope bias calibration with custom sample count and motion threshold.
    pub fn recalibrate_with(&mut self, samples: usize, threshold: f32) {
        self.last_calibration_error = None;
        self.calibrator = Some(Calibrator::new(samples, threshold));
    }

    /// Returns `true` while a calibration started by [`Engine::recalibrate`] is still collecting samples.
    pub const fn is_calibrating(&self) -> bool {
        self.calibrator.is_some()
    }

    /// Returns the currently applied gyroscope bias vector (in rad/s).
    pub const fn gyro_bias(&self) -> Vec3 {
        self.gyro_bias
    }

    /// Explicitly sets the gyroscope bias vector (in rad/s).
    pub fn set_gyro_bias(&mut self, bias: Vec3) {
        self.gyro_bias = bias;
    }

    /// Returns the error from the most recent calibration attempt, if it failed.
    pub const fn last_calibration_error(&self) -> Option<CalibrationError> {
        self.last_calibration_error
    }

    /// Helper returning `true` when battery percentage `level` is below 15%.
    #[inline]
    pub const fn battery_low(level: u8) -> bool {
        battery_low(level)
    }

    /// Advances button and tap timers at timestamp `t_us` (in µs) without a new BLE packet
    /// (firing long-press thresholds and expiring double-press windows).
    pub fn tick(&mut self, t_us: u64) -> Vec<Action> {
        if self.test_mode {
            return Vec::new();
        }
        let mut out = std::mem::take(&mut self.pending_actions);
        let sample = self.last_sample.unwrap_or_default();
        self.step_buttons(&sample, t_us, &mut out);
        out
    }

    /// Feeds a 20-byte Daydream BLE notification `packet` received at timestamp `t_us` (in µs)
    /// and returns the resulting output [`Action`]s in deterministic order.
    pub fn feed(&mut self, packet: &[u8; 20], t_us: u64) -> Vec<Action> {
        let sample = daydream::decode(packet);
        self.last_sample = Some(sample);

        if let Some(mut cal) = self.calibrator.take() {
            match cal.push(&sample) {
                None => {
                    self.calibrator = Some(cal);
                }
                Some(Ok(bias)) => {
                    self.gyro_bias = bias;
                    self.last_calibration_error = None;
                }
                Some(Err(err)) => {
                    self.last_calibration_error = Some(err);
                }
            }
        }

        if self.test_mode {
            return Vec::new();
        }

        let mut out = std::mem::take(&mut self.pending_actions);

        // 1 & 2. Update button & tap state machines and active radial menu hold.
        self.step_buttons(&sample, t_us, &mut out);

        // 3. Pointer motion (touch mode or gyro mode).
        let (prev_px, prev_py) = self.pointer.last_point();
        match self.pointer.update_at(
            &sample,
            self.mode,
            &self.config.settings,
            self.gyro_bias,
            t_us,
        ) {
            Some(Action::Move { dx, dy }) => {
                if let Some(radial) = &mut self.radial {
                    radial.dx += dx;
                    radial.dy += dy;
                }
                out.push(Action::Move { dx, dy });
            }
            Some(Action::PointTo { x, y }) => {
                if let Some(radial) = &mut self.radial {
                    let scale = self.config.settings.screen_width_px as f32;
                    radial.dx += (x - prev_px) * scale;
                    radial.dy += (y - prev_py) * scale;
                }
                out.push(Action::PointTo { x, y });
            }
            Some(other) => out.push(other),
            None => {}
        }

        // 4. In gyro mode, touchpad swipes either scroll (Desktop / Android) or move D-pad focus (AndroidTv).
        if self.mode == PointerMode::Gyro {
            if let Some(touch_action) = self.update_gyro_touchpad(&sample) {
                out.push(touch_action);
            }
        }

        out
    }

    fn step_buttons(&mut self, sample: &Sample, t_us: u64, out: &mut Vec<Action>) {
        let tap_enabled = match self.mode {
            PointerMode::Touch => self.config.settings.tap_in_touch_mode,
            PointerMode::Gyro => self.config.settings.tap_in_gyro_mode,
        };
        let long_press_us = self.config.settings.long_press_ms.saturating_mul(1_000);
        let double_press_us = self.config.settings.double_press_ms.saturating_mul(1_000);

        let raw_button_actions = self.buttons.update(
            sample,
            t_us,
            &self.config.bindings,
            long_press_us,
            double_press_us,
            tap_enabled,
        );

        for action in raw_button_actions {
            match action {
                Action::ToggleGyro => {
                    self.set_gyro_mode(!self.gyro_mode());
                    out.push(Action::ToggleGyro);
                }
                Action::Recenter => {
                    self.recenter();
                    out.push(Action::Recenter);
                }
                Action::Scroll { dx, dy } => {
                    let sign = if self.config.settings.reverse_scroll {
                        -1.0
                    } else {
                        1.0
                    };
                    let strength = self.config.settings.scroll_strength;
                    out.push(Action::Scroll {
                        dx: dx * strength * sign,
                        dy: dy * strength * sign,
                    });
                }
                Action::RadialMenu => {
                    // Check if radial menu is held; track offset until release.
                    if let Some((btn, press)) = self.find_active_radial_hold() {
                        self.radial = Some(ActiveRadial {
                            button: btn,
                            press,
                            dx: 0.0,
                            dy: 0.0,
                        });
                    }
                    out.push(Action::RadialMenu);
                }
                other => out.push(other),
            }
        }

        // Check if an active radial menu hold was released.
        if let Some(active) = &self.radial {
            if !self.buttons.is_hold_active(active.button, active.press) {
                let finished = self.radial.take().unwrap();
                if let Some(slot_idx) = slot_for(
                    finished.dx,
                    finished.dy,
                    self.config.settings.radial_dead_radius,
                ) {
                    if let Some(slot) = self.config.radial_slots.get(slot_idx as usize) {
                        if let Some(slot_action) = &slot.action {
                            out.push(slot_action.clone());
                        }
                    }
                }
            }
        }
    }

    fn find_active_radial_hold(&self) -> Option<(Button, Press)> {
        for ((btn, press), binding) in &self.config.bindings {
            if binding.action == Action::RadialMenu && self.buttons.is_hold_active(*btn, *press) {
                return Some((*btn, *press));
            }
        }
        None
    }

    fn update_gyro_touchpad(&mut self, sample: &Sample) -> Option<Action> {
        if !sample.touching {
            // On Android TV, if a shorter swipe completed on touch release, emit DPad.
            if self.platform == Platform::AndroidTv && !self.gyro_touch.swipe_emitted {
                if let (Some((ax, ay)), Some((lx, ly))) =
                    (self.gyro_touch.swipe_anchor, self.gyro_touch.last_pos)
                {
                    let dx = lx - ax;
                    let dy = ly - ay;
                    if dx.abs() >= TV_SWIPE_THRESHOLD || dy.abs() >= TV_SWIPE_THRESHOLD {
                        self.gyro_touch.reset();
                        return Some(Action::DPad(dominant_direction(dx, dy)));
                    }
                }
            }
            self.gyro_touch.reset();
            return None;
        }

        let pos = (sample.touch_x, sample.touch_y);
        let Some((prev_x, prev_y)) = self.gyro_touch.last_pos.replace(pos) else {
            // First touch sample: anchor and avoid jump.
            self.gyro_touch.swipe_anchor = Some(pos);
            self.gyro_touch.swipe_emitted = false;
            return None;
        };

        if self.platform == Platform::AndroidTv {
            if self.gyro_touch.swipe_emitted {
                return None;
            }
            if let Some((ax, ay)) = self.gyro_touch.swipe_anchor {
                let total_dx = sample.touch_x - ax;
                let total_dy = sample.touch_y - ay;
                if total_dx.abs() >= TV_SWIPE_THRESHOLD || total_dy.abs() >= TV_SWIPE_THRESHOLD {
                    self.gyro_touch.swipe_emitted = true;
                    return Some(Action::DPad(dominant_direction(total_dx, total_dy)));
                }
            }
            None
        } else {
            let raw_dx = sample.touch_x - prev_x;
            let raw_dy = sample.touch_y - prev_y;
            let mag = (raw_dx * raw_dx + raw_dy * raw_dy).sqrt();
            if mag <= self.config.settings.touch_deadzone {
                return None;
            }

            let sign = if self.config.settings.reverse_scroll {
                -1.0
            } else {
                1.0
            };
            let strength = self.config.settings.scroll_strength;
            let dy = raw_dy * strength * sign;
            let dx = if self.config.settings.horizontal_scroll {
                raw_dx * strength * sign
            } else {
                0.0
            };

            if dx == 0.0 && dy == 0.0 {
                None
            } else {
                Some(Action::Scroll { dx, dy })
            }
        }
    }
}

fn dominant_direction(dx: f32, dy: f32) -> Direction {
    if dx.abs() >= dy.abs() {
        if dx >= 0.0 {
            Direction::Right
        } else {
            Direction::Left
        }
    } else if dy >= 0.0 {
        Direction::Down
    } else {
        Direction::Up
    }
}
