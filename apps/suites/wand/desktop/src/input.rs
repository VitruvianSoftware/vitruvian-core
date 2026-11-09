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

//! Input worker thread owning [`wand_core::Engine`] and [`crate::injector::Injector`],
//! plus deterministic replay session execution.

use crate::config::get_gyro_touchpad_scroll;
use crate::glide::{GLIDE_TICK_US, Glide};
#[cfg(not(target_os = "macos"))]
use crate::injector::FakeInjector;
use crate::injector::Injector;
use crate::radial_overlay::RadialOverlayController;
use crate::status::Status;
use std::sync::{Arc, Mutex, mpsc};
use std::thread::{self, JoinHandle};
use std::time::Duration;
use wand_core::replay::parse as parse_replay;
use wand_core::{Action, Config, Engine, Platform, ReplayError, Sample};

/// Interval at which the input worker thread advances button timers when no BLE packet arrives.
pub const INPUT_TICK_INTERVAL: Duration = Duration::from_millis(20);

/// Interval at which the input worker thread steps [`Glide`] interpolation (125 Hz = `8 ms`).
pub const GLIDE_TICK_INTERVAL: Duration = Duration::from_micros(GLIDE_TICK_US);

/// Commands sent from the BLE thread or UI thread to the input thread.
#[derive(Debug, Clone)]
pub enum InputCommand {
    /// Feed a 20-byte Daydream notification packet with monotonic timestamp `t_us` (in µs).
    Packet { bytes: [u8; 20], t_us: u64 },
    /// Advance button/tap timers to monotonic timestamp `t_us` (in µs) without a packet.
    Tick { t_us: u64 },
    /// Release all active Hold/Toggle actions, close any open radial menu, and reset button state.
    ReleaseAll,
    /// Replace the active [`Config`] on the engine.
    UpdateConfig(Config),
    /// Explicitly set gyro pointer mode on or off.
    SetGyroMode(bool),
    /// Toggle gyro pointer mode.
    ToggleGyroMode,
    /// Enable or disable live visualizer test mode.
    SetTestMode(bool),
    /// Start stationary gyroscope bias calibration.
    Recalibrate,
    /// Shut down the input worker thread (releasing any held actions first).
    Shutdown,
}

/// Alias for [`InputCommand`].
pub type InputCmd = InputCommand;

/// Creates the platform's default [`Injector`] (`MacosInjector` on macOS, `LinuxInjector` on Linux,
/// falling back to [`FakeInjector`] if OS permissions/devices are unavailable).
pub fn create_platform_injector() -> (Box<dyn Injector>, bool, String) {
    #[cfg(target_os = "macos")]
    {
        let trusted = crate::macos::is_accessibility_trusted();
        let msg = if trusted {
            "Accessibility permission granted".to_string()
        } else {
            "Accessibility permission required to inject pointer & key events".to_string()
        };
        (Box::new(crate::macos::MacosInjector::new()), trusted, msg)
    }

    #[cfg(target_os = "linux")]
    {
        match crate::linux::LinuxInjector::new() {
            Ok(inj) => (
                Box::new(inj),
                true,
                "/dev/uinput virtual device ready".to_string(),
            ),
            Err(err) => (Box::new(FakeInjector::new()), false, err.0),
        }
    }

    #[cfg(not(any(target_os = "macos", target_os = "linux")))]
    {
        (
            Box::new(FakeInjector::new()),
            true,
            "Fallback injector".to_string(),
        )
    }
}

/// Deterministic input pipeline coupling [`Engine`], [`RadialOverlayController`], [`Glide`], and [`Injector`].
pub struct InputPipeline {
    engine: Engine,
    injector: Box<dyn Injector>,
    radial: RadialOverlayController,
    glide: Glide,
    gyro_touchpad_scroll: bool,
    prev_buttons: (bool, bool, bool, bool, bool),
    last_point_to: (f32, f32),
    last_t_us: u64,
    status: Arc<Mutex<Status>>,
}

impl InputPipeline {
    /// Creates a new [`InputPipeline`] owning `engine` and `injector`.
    pub fn new(
        config: Config,
        mut injector: Box<dyn Injector>,
        status: Arc<Mutex<Status>>,
    ) -> Self {
        let config = config.sanitized();
        injector.set_screen_width_px(config.settings.screen_width_px);
        let dead_radius = config.settings.radial_dead_radius;
        let gyro_touchpad_scroll = get_gyro_touchpad_scroll(&config);
        let engine = Engine::new(config, Platform::Desktop);
        Self {
            engine,
            injector,
            radial: RadialOverlayController::new(dead_radius),
            glide: Glide::new(),
            gyro_touchpad_scroll,
            prev_buttons: (false, false, false, false, false),
            last_point_to: (0.0, 0.0),
            last_t_us: 0,
            status,
        }
    }

    /// Returns a reference to the underlying [`Engine`].
    pub const fn engine(&self) -> &Engine {
        &self.engine
    }

    /// Returns a reference to the cursor [`Glide`] interpolator.
    pub const fn glide(&self) -> &Glide {
        &self.glide
    }

    /// Returns `true` when motion glide is enabled and a glide segment is currently active.
    pub fn is_gliding(&self) -> bool {
        self.engine.config().settings.motion_glide && self.glide.is_active()
    }

    /// Returns the last monotonic timestamp `t_us` processed by the pipeline.
    pub const fn last_t_us(&self) -> u64 {
        self.last_t_us
    }

    /// Processes a single command on the input pipeline.
    pub fn handle_command(&mut self, cmd: InputCommand) {
        match cmd {
            InputCommand::Packet { bytes, t_us } => {
                let _ = self.process_packet(&bytes, t_us);
            }
            InputCommand::Tick { t_us } => {
                let _ = self.tick(t_us);
            }
            InputCommand::ReleaseAll => {
                let _ = self.release_all();
            }
            InputCommand::UpdateConfig(cfg) => {
                let cfg = cfg.sanitized();
                if !cfg.settings.motion_glide
                    || cfg.settings.pointing_mode != self.engine.config().settings.pointing_mode
                {
                    self.glide.reset();
                }
                self.injector
                    .set_screen_width_px(cfg.settings.screen_width_px);
                self.radial.set_dead_radius(cfg.settings.radial_dead_radius);
                self.gyro_touchpad_scroll = get_gyro_touchpad_scroll(&cfg);
                self.engine.set_config(cfg);
            }
            InputCommand::SetGyroMode(enabled) => {
                self.engine.set_gyro_mode(enabled);
                self.last_point_to = (0.0, 0.0);
                self.glide.reset();
                self.sync_status();
            }
            InputCommand::ToggleGyroMode => {
                self.engine.set_gyro_mode(!self.engine.gyro_mode());
                self.last_point_to = (0.0, 0.0);
                self.glide.reset();
                self.sync_status();
            }
            InputCommand::SetTestMode(enabled) => {
                if enabled {
                    let _ = self.release_all();
                }
                self.engine.set_test_mode(enabled);
                self.sync_status();
            }
            InputCommand::Recalibrate => {
                self.engine.recalibrate();
                self.sync_status();
            }
            InputCommand::Shutdown => {
                let _ = self.release_all();
            }
        }
    }

    /// Releases all active Hold and Toggle bindings on the engine, closes any open radial overlay
    /// without executing a slot, resets [`Glide`], and applies the resulting release actions to
    /// the [`Injector`].
    pub fn release_all(&mut self) -> Vec<Action> {
        let actions = self.engine.release_all();
        if self.radial.is_open() {
            let _ = self.radial.release(&[]);
        }
        self.prev_buttons = (false, false, false, false, false);
        self.last_point_to = (0.0, 0.0);
        self.glide.reset();
        for action in &actions {
            if let Err(err) = self.injector.apply(action) {
                log::debug!("Injector error on release_all {action:?}: {err}");
            }
        }
        self.sync_status();
        actions
    }

    /// Advances button/tap timers and any active [`Glide`] interpolation to `t_us` without a packet,
    /// applying any emitted actions to the [`Injector`].
    pub fn tick(&mut self, t_us: u64) -> Vec<Action> {
        self.last_t_us = t_us;
        let mut actions = self.engine.tick(t_us);
        if !self.engine.is_radial_active() && self.radial.is_open() {
            let _ = self.radial.release(&[]);
        }
        for action in &actions {
            match action {
                Action::RadialMenu => {
                    self.radial.open();
                }
                Action::ToggleGyro | Action::Recenter => {
                    self.last_point_to = (0.0, 0.0);
                    self.glide.reset();
                    if let Err(err) = self.injector.apply(action) {
                        log::debug!("Injector error on tick {action:?}: {err}");
                    }
                }
                other => {
                    if let Err(err) = self.injector.apply(other) {
                        log::debug!("Injector error on tick {other:?}: {err}");
                    }
                }
            }
        }
        if self.engine.config().settings.motion_glide
            && let Some((gx, gy)) = self.glide.step(t_us)
        {
            let pt = Action::PointTo { x: gx, y: gy };
            if let Err(err) = self.injector.apply(&pt) {
                log::debug!("Injector error on glide tick PointTo: {err}");
            }
            actions.push(pt);
        }
        if !actions.is_empty() {
            self.sync_status();
        }
        actions
    }

    /// Feeds a 20-byte packet at `t_us` into [`Engine`], updates the radial overlay state,
    /// applies output [`Action`]s to the [`Injector`], and updates shared [`Status`].
    pub fn process_packet(&mut self, packet: &[u8; 20], t_us: u64) -> Vec<Action> {
        self.last_t_us = t_us;
        let mut actions = self.engine.feed(packet, t_us);
        let sample = self.engine.last_sample().copied();

        if let Some(s) = sample {
            let cur_buttons = (s.click, s.home, s.app, s.vol_down, s.vol_up);
            let buttons_unchanged = cur_buttons == self.prev_buttons;
            self.prev_buttons = cur_buttons;

            // If touchpad scrolling in gyro mode is toggled off, suppress the trailing touchpad Scroll
            // when the user is swiping the touchpad without pressing/releasing any buttons.
            if !self.gyro_touchpad_scroll
                && self.engine.gyro_mode()
                && s.touching
                && buttons_unchanged
                && matches!(actions.last(), Some(Action::Scroll { .. }))
            {
                actions.pop();
            }

            // Engine is the single owner of radial slot execution; close the visual overlay
            // when the engine's radial menu closes.
            if self.radial.is_open() && !self.engine.is_radial_active() {
                let _ = self.radial.release(&[]);
            }
        }

        for action in &actions {
            match action {
                Action::RadialMenu => {
                    self.radial.open();
                }
                Action::ToggleGyro | Action::Recenter => {
                    self.last_point_to = (0.0, 0.0);
                    self.glide.reset();
                    if let Err(err) = self.injector.apply(action) {
                        log::debug!("Injector error on {action:?}: {err}");
                    }
                }
                Action::Move { dx, dy } => {
                    if self.radial.is_open() {
                        self.radial.feed_move(*dx, *dy);
                    }
                    if let Err(err) = self.injector.apply(action) {
                        log::debug!("Injector error on Move: {err}");
                    }
                }
                Action::PointTo { x, y } => {
                    let (prev_x, prev_y) = self.last_point_to;
                    self.last_point_to = (*x, *y);
                    if self.radial.is_open() {
                        let scale = self.engine.config().settings.screen_width_px as f32;
                        self.radial
                            .feed_move((*x - prev_x) * scale, (*y - prev_y) * scale);
                    }
                    if self.engine.config().settings.motion_glide {
                        if let Some((gx, gy)) = self.glide.on_point_to((*x, *y), t_us)
                            && let Err(err) = self.injector.apply(&Action::PointTo { x: gx, y: gy })
                        {
                            log::debug!("Injector error on PointTo: {err}");
                        }
                    } else {
                        self.glide.reset();
                        if let Err(err) = self.injector.apply(action) {
                            log::debug!("Injector error on PointTo: {err}");
                        }
                    }
                }
                other => {
                    if let Err(err) = self.injector.apply(other) {
                        log::debug!("Injector error on {other:?}: {err}");
                    }
                }
            }
        }

        self.sync_status_with_sample(sample);
        actions
    }

    fn sync_status(&self) {
        self.sync_status_with_sample(self.engine.last_sample().copied());
    }

    fn sync_status_with_sample(&self, sample: Option<Sample>) {
        if let Ok(mut st) = self.status.lock() {
            if let Some(s) = sample {
                st.last_sample = Some(s);
            }
            st.gyro_mode = self.engine.gyro_mode();
            st.test_mode = self.engine.is_test_mode();
            st.calibrating = self.engine.is_calibrating();
            st.calibration_error = self.engine.last_calibration_error().map(|e| e.to_string());
            st.radial_open = self.radial.is_open();
            st.radial_offset = self.radial.offset();
            st.radial_selected_slot = self.radial.selected_slot();
        }
    }
}

/// Spawns the dedicated input thread that owns [`Engine`] and [`Injector`].
pub fn spawn_input_thread(
    config: Config,
    injector: Box<dyn Injector>,
    status: Arc<Mutex<Status>>,
) -> (mpsc::Sender<InputCommand>, JoinHandle<()>) {
    let (tx, rx) = mpsc::channel::<InputCommand>();
    let handle = thread::Builder::new()
        .name("wand-input".to_string())
        .spawn(move || {
            let mut pipeline = InputPipeline::new(config, injector, status);
            loop {
                let tick_interval = if pipeline.is_gliding() {
                    GLIDE_TICK_INTERVAL
                } else {
                    INPUT_TICK_INTERVAL
                };
                let step_us = tick_interval.as_micros() as u64;
                match rx.recv_timeout(tick_interval) {
                    Ok(InputCommand::Shutdown) | Err(mpsc::RecvTimeoutError::Disconnected) => {
                        pipeline.handle_command(InputCommand::Shutdown);
                        break;
                    }
                    Ok(cmd) => {
                        pipeline.handle_command(cmd);
                    }
                    Err(mpsc::RecvTimeoutError::Timeout) => {
                        let next_t = pipeline.last_t_us().saturating_add(step_us);
                        let _ = pipeline.tick(next_t);
                    }
                }
            }
        })
        .expect("failed to spawn wand-input thread");
    (tx, handle)
}

/// Drives `engine` and `injector` from a `.replay` transcript string and returns all emitted [`Action`]s.
///
/// When `engine.config().settings.motion_glide` is `true`, `PointTo` actions are interpolated
/// through [`Glide`] with 125 Hz (`8 ms`) ticks between packets and until any active glide completes.
pub fn drive_replay_with_injector(
    engine: &mut Engine,
    replay_text: &str,
    injector: &mut dyn Injector,
) -> Result<Vec<Action>, ReplayError> {
    let records = parse_replay(replay_text)?;
    let mut emitted = Vec::new();
    if !engine.config().settings.motion_glide {
        for rec in records {
            let step_actions = engine.feed(&rec.packet, rec.t_us);
            for action in &step_actions {
                let _ = injector.apply(action);
            }
            emitted.extend(step_actions);
        }
        return Ok(emitted);
    }

    let mut glide = Glide::new();
    let mut next_tick_us: Option<u64> = None;

    for rec in records {
        while glide.is_active()
            && let Some(tick_t) = next_tick_us
            && tick_t <= rec.t_us
        {
            if let Some((gx, gy)) = glide.step(tick_t) {
                let act = Action::PointTo { x: gx, y: gy };
                let _ = injector.apply(&act);
                emitted.push(act);
            }
            if glide.is_active() {
                next_tick_us = Some(tick_t.saturating_add(GLIDE_TICK_US));
            } else {
                next_tick_us = None;
            }
        }

        let step_actions = engine.feed(&rec.packet, rec.t_us);
        for action in step_actions {
            match action {
                Action::ToggleGyro | Action::Recenter => {
                    glide.reset();
                    next_tick_us = None;
                    let _ = injector.apply(&action);
                    emitted.push(action);
                }
                Action::PointTo { x, y } => {
                    if let Some((gx, gy)) = glide.on_point_to((x, y), rec.t_us) {
                        let act = Action::PointTo { x: gx, y: gy };
                        let _ = injector.apply(&act);
                        emitted.push(act);
                    }
                    if glide.is_active() && next_tick_us.is_none() {
                        next_tick_us = Some(rec.t_us.saturating_add(GLIDE_TICK_US));
                    }
                }
                other => {
                    let _ = injector.apply(&other);
                    emitted.push(other);
                }
            }
        }
    }

    while glide.is_active()
        && let Some(tick_t) = next_tick_us
    {
        if let Some((gx, gy)) = glide.step(tick_t) {
            let act = Action::PointTo { x: gx, y: gy };
            let _ = injector.apply(&act);
            emitted.push(act);
        }
        if glide.is_active() {
            next_tick_us = Some(tick_t.saturating_add(GLIDE_TICK_US));
        } else {
            next_tick_us = None;
        }
    }

    Ok(emitted)
}
