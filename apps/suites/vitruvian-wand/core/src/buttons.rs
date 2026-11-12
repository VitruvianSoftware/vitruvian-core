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

//! Per-button short/long/double press state machine, touchpad tap detector,
//! and Once/Hold/Toggle trigger resolution.

use crate::bindings::{Action, Binding, Bindings, Button, Press, TriggerMode};
use crate::protocol::daydream::Sample;
use std::collections::BTreeSet;

/// Default long-press threshold in microseconds (500 ms).
pub const DEFAULT_LONG_PRESS_US: u64 = 500_000;

/// Default maximum gap between presses for a double press in microseconds (300 ms).
pub const DEFAULT_DOUBLE_PRESS_US: u64 = 300_000;

/// Maximum touch duration for a touchpad tap gesture in microseconds (200 ms).
pub const DEFAULT_TAP_MAX_US: u64 = 200_000;

/// Maximum normalized touch travel allowed during a touchpad tap (`0.05` in `0.0..=1.0`).
pub const DEFAULT_TAP_MAX_MOVE: f32 = 0.05;

/// Low-level button gesture transition emitted by [`SingleButtonMachine`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PressEvent {
    /// Immediate press start (used when `Press::Short` has `TriggerMode::Hold` and neither
    /// `Press::Long` nor `Press::Double` is bound on the same button).
    ShortHoldStart,
    /// Release of an immediate `Press::Short` hold.
    ShortHoldEnd,
    /// Completed short press.
    Short,
    /// Long press threshold reached while button is still held.
    LongStart,
    /// Button released after a long press was triggered.
    LongEnd,
    /// Second press of a double-press started within the double-press gap.
    DoubleStart,
    /// Second press of a double-press released.
    DoubleEnd,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
enum SingleState {
    #[default]
    Idle,
    HeldImmediate,
    FirstDown {
        since_us: u64,
        long_fired: bool,
    },
    WaitDouble {
        release_us: u64,
    },
    SecondDown {
        since_us: u64,
    },
}

/// Deterministic state machine for a single physical button.
#[derive(Debug, Clone, Default)]
pub struct SingleButtonMachine {
    state: SingleState,
}

impl SingleButtonMachine {
    /// Creates a new idle [`SingleButtonMachine`].
    pub const fn new() -> Self {
        Self {
            state: SingleState::Idle,
        }
    }

    /// Resets the state machine back to `Idle`.
    pub fn reset(&mut self) {
        self.state = SingleState::Idle;
    }

    /// Advances the button state machine at timestamp `t_us` with current `down` state.
    ///
    /// - `has_long`: whether a `Press::Long` binding is configured for this button. When `false`,
    ///   holding past `long_press_us` never fires `LongStart`/`LongEnd`, and releasing after any
    ///   hold duration resolves as a short press (or enters `WaitDouble` if `has_double`).
    /// - `has_double`: whether a `Press::Double` binding is configured for this button. When `false`,
    ///   a short press fires immediately on release without waiting `double_press_us`.
    /// - `short_is_hold`: whether `Press::Short` uses `TriggerMode::Hold` AND neither `Long` nor
    ///   `Double` is bound on the same button. Immediate-on-press (`ShortHoldStart` on physical
    ///   button down) only applies when no `Long` or `Double` binding is present; when `Long` or
    ///   `Double` is also bound, `Press::Short` with `TriggerMode::Hold` waits until the press is
    ///   resolved as `Short` (on release before `long_press_us`) and then emits its down+up pair.
    #[allow(clippy::too_many_arguments)]
    pub fn update(
        &mut self,
        down: bool,
        t_us: u64,
        long_press_us: u64,
        double_press_us: u64,
        has_long: bool,
        has_double: bool,
        short_is_hold: bool,
    ) -> Vec<PressEvent> {
        let mut events = Vec::new();

        match self.state {
            SingleState::Idle => {
                if down {
                    if short_is_hold {
                        self.state = SingleState::HeldImmediate;
                        events.push(PressEvent::ShortHoldStart);
                    } else {
                        self.state = SingleState::FirstDown {
                            since_us: t_us,
                            long_fired: false,
                        };
                    }
                }
            }
            SingleState::HeldImmediate => {
                if !down {
                    self.state = SingleState::Idle;
                    events.push(PressEvent::ShortHoldEnd);
                }
            }
            SingleState::FirstDown {
                since_us,
                mut long_fired,
            } => {
                if down {
                    if has_long && !long_fired && t_us.saturating_sub(since_us) >= long_press_us {
                        long_fired = true;
                        self.state = SingleState::FirstDown {
                            since_us,
                            long_fired,
                        };
                        events.push(PressEvent::LongStart);
                    }
                } else if long_fired {
                    self.state = SingleState::Idle;
                    events.push(PressEvent::LongEnd);
                } else if has_long && t_us.saturating_sub(since_us) >= long_press_us {
                    // Released on or after the long-press threshold in a single step.
                    self.state = SingleState::Idle;
                    events.push(PressEvent::LongStart);
                    events.push(PressEvent::LongEnd);
                } else if has_double {
                    self.state = SingleState::WaitDouble { release_us: t_us };
                } else {
                    self.state = SingleState::Idle;
                    events.push(PressEvent::Short);
                }
            }
            SingleState::WaitDouble { release_us } => {
                let elapsed = t_us.saturating_sub(release_us);
                if down {
                    if elapsed <= double_press_us {
                        self.state = SingleState::SecondDown { since_us: t_us };
                        events.push(PressEvent::DoubleStart);
                    } else {
                        // Double-press window expired before this press: flush pending Short first.
                        events.push(PressEvent::Short);
                        if short_is_hold {
                            self.state = SingleState::HeldImmediate;
                            events.push(PressEvent::ShortHoldStart);
                        } else {
                            self.state = SingleState::FirstDown {
                                since_us: t_us,
                                long_fired: false,
                            };
                        }
                    }
                } else if elapsed > double_press_us {
                    self.state = SingleState::Idle;
                    events.push(PressEvent::Short);
                }
            }
            SingleState::SecondDown { since_us: _ } => {
                if !down {
                    self.state = SingleState::Idle;
                    events.push(PressEvent::DoubleEnd);
                }
            }
        }

        events
    }
}

#[derive(Debug, Clone, Copy)]
struct TapAttempt {
    start_us: u64,
    start_x: f32,
    start_y: f32,
    max_move: f32,
    clicked: bool,
    long_fired: bool,
}

/// Touchpad tap detector supporting:
/// - `Short`: touch-down to touch-up within `tap_max_us` with travel `< tap_max_move` and without click.
/// - `Long`: touch held stationary (`< tap_max_move`) without click for `>= long_press_us`.
/// - `Double`: two short taps within `double_press_us`.
#[derive(Debug, Clone, Default)]
pub struct TapDetector {
    attempt: Option<TapAttempt>,
    waiting_double_release_us: Option<u64>,
}

impl TapDetector {
    /// Creates a new [`TapDetector`].
    pub const fn new() -> Self {
        Self {
            attempt: None,
            waiting_double_release_us: None,
        }
    }

    /// Resets any in-progress tap tracking.
    pub fn reset(&mut self) {
        self.attempt = None;
        self.waiting_double_release_us = None;
    }

    /// Updates the tap detector for a single short tap without `Long` or `Double` bindings.
    /// Returns `true` when a valid touchpad tap completes on touch release.
    pub fn update(
        &mut self,
        sample: &Sample,
        t_us: u64,
        tap_max_us: u64,
        tap_max_move: f32,
    ) -> bool {
        let events = self.update_events(
            sample,
            t_us,
            tap_max_us,
            tap_max_move,
            DEFAULT_LONG_PRESS_US,
            DEFAULT_DOUBLE_PRESS_US,
            false,
            false,
        );
        events.contains(&PressEvent::Short)
    }

    /// Advances the touchpad tap state machine (for `Short`, `Long`, and `Double` tap gestures)
    /// and returns any resulting [`PressEvent`]s.
    #[allow(clippy::too_many_arguments)]
    pub fn update_events(
        &mut self,
        sample: &Sample,
        t_us: u64,
        tap_max_us: u64,
        tap_max_move: f32,
        long_press_us: u64,
        double_press_us: u64,
        has_long: bool,
        has_double: bool,
    ) -> Vec<PressEvent> {
        let mut events = Vec::new();

        if sample.touching {
            if self.attempt.is_none() {
                if let Some(rel_us) = self.waiting_double_release_us {
                    if t_us.saturating_sub(rel_us) > double_press_us {
                        self.waiting_double_release_us = None;
                        events.push(PressEvent::Short);
                    }
                }
                self.attempt = Some(TapAttempt {
                    start_us: t_us,
                    start_x: sample.touch_x,
                    start_y: sample.touch_y,
                    max_move: 0.0,
                    clicked: sample.click,
                    long_fired: false,
                });
            } else if let Some(att) = &mut self.attempt {
                let dx = sample.touch_x - att.start_x;
                let dy = sample.touch_y - att.start_y;
                let dist = (dx * dx + dy * dy).sqrt();
                if dist > att.max_move {
                    att.max_move = dist;
                }
                att.clicked |= sample.click;
            }

            if let Some(att) = &mut self.attempt {
                let invalid_short = att.clicked
                    || att.max_move >= tap_max_move
                    || t_us.saturating_sub(att.start_us) > tap_max_us;
                if invalid_short && self.waiting_double_release_us.is_some() {
                    self.waiting_double_release_us = None;
                    events.push(PressEvent::Short);
                }

                if has_long
                    && !att.long_fired
                    && !att.clicked
                    && att.max_move < tap_max_move
                    && t_us.saturating_sub(att.start_us) >= long_press_us
                {
                    att.long_fired = true;
                    events.push(PressEvent::LongStart);
                }
            }
        } else if let Some(att) = self.attempt.take() {
            let valid_still = !att.clicked && !sample.click && att.max_move < tap_max_move;
            let duration = t_us.saturating_sub(att.start_us);

            if att.long_fired {
                events.push(PressEvent::LongEnd);
            } else if has_long && valid_still && duration >= long_press_us {
                events.push(PressEvent::LongStart);
                events.push(PressEvent::LongEnd);
            } else if valid_still && duration <= tap_max_us {
                if let Some(rel_us) = self.waiting_double_release_us.take() {
                    if att.start_us.saturating_sub(rel_us) <= double_press_us {
                        events.push(PressEvent::DoubleStart);
                        events.push(PressEvent::DoubleEnd);
                    } else {
                        events.push(PressEvent::Short);
                        if has_double {
                            self.waiting_double_release_us = Some(t_us);
                        } else {
                            events.push(PressEvent::Short);
                        }
                    }
                } else if has_double {
                    self.waiting_double_release_us = Some(t_us);
                } else {
                    events.push(PressEvent::Short);
                }
            } else if let Some(rel_us) = self.waiting_double_release_us {
                if t_us.saturating_sub(rel_us) > double_press_us {
                    self.waiting_double_release_us = None;
                    events.push(PressEvent::Short);
                }
            }
        } else if let Some(rel_us) = self.waiting_double_release_us {
            if t_us.saturating_sub(rel_us) > double_press_us {
                self.waiting_double_release_us = None;
                events.push(PressEvent::Short);
            }
        }

        events
    }
}

/// Converts a bound [`Action`] into its press-down counterpart for [`TriggerMode::Hold`] and [`TriggerMode::Toggle`].
pub fn hold_down_action(action: &Action) -> Action {
    match action {
        Action::LeftClick | Action::MouseDown | Action::MouseUp => Action::MouseDown,
        other => other.clone(),
    }
}

/// Converts a bound [`Action`] into its release/off counterpart for [`TriggerMode::Hold`] and [`TriggerMode::Toggle`].
pub fn hold_up_action(action: &Action) -> Option<Action> {
    match action {
        Action::LeftClick | Action::MouseDown | Action::MouseUp => Some(Action::MouseUp),
        _ => None,
    }
}

/// Full controller button & tap state machine resolving [`Bindings`] and [`TriggerMode`]s into [`Action`]s.
#[derive(Debug, Clone, Default)]
pub struct ButtonMachine {
    machines: [SingleButtonMachine; 5],
    tap: TapDetector,
    toggled_slots: BTreeSet<(Button, Press)>,
    active_holds: BTreeSet<(Button, Press)>,
}

impl ButtonMachine {
    /// Creates a new [`ButtonMachine`].
    pub fn new() -> Self {
        Self::default()
    }

    /// Resets all button, tap, hold, and toggle states.
    pub fn reset(&mut self) {
        for m in &mut self.machines {
            m.reset();
        }
        self.tap.reset();
        self.toggled_slots.clear();
        self.active_holds.clear();
    }

    /// Releases all active [`TriggerMode::Hold`] and [`TriggerMode::Toggle`] bindings,
    /// returning their corresponding release [`Action`]s (e.g. [`Action::MouseUp`]),
    /// and resets all button and tap machines.
    pub fn release_all(&mut self, bindings: &Bindings) -> Vec<Action> {
        let mut out = Vec::new();
        let mut slots = BTreeSet::new();
        slots.extend(std::mem::take(&mut self.active_holds));
        slots.extend(std::mem::take(&mut self.toggled_slots));
        for slot in slots {
            if let Some(binding) = bindings.get(&slot) {
                if let Some(up) = hold_up_action(&binding.action) {
                    out.push(up);
                }
            }
        }
        self.reset();
        out
    }

    /// Processes a [`Sample`] at timestamp `t_us` (in microseconds) and returns all triggered [`Action`]s.
    ///
    /// Note on `TriggerMode::Hold` for `Press::Short`:
    /// - When neither `Press::Long` nor `Press::Double` is bound on the same button, `Hold` starts
    ///   immediately on physical button down (`ShortHoldStart`) and releases on physical button up.
    /// - When `Press::Long` or `Press::Double` is also bound on the same button, the engine cannot
    ///   know at button-down whether the press will become `Long` or `Double`; once the press resolves
    ///   as `Press::Short` (e.g. on release before `long_press_us`), `Hold` emits its down+up pair.
    pub fn update(
        &mut self,
        sample: &Sample,
        t_us: u64,
        bindings: &Bindings,
        long_press_us: u64,
        double_press_us: u64,
        tap_enabled: bool,
    ) -> Vec<Action> {
        let mut actions = Vec::new();

        let button_states: [(Button, bool); 5] = [
            (Button::Click, sample.click),
            (Button::App, sample.app),
            (Button::Home, sample.home),
            (Button::VolUp, sample.vol_up),
            (Button::VolDown, sample.vol_down),
        ];

        for (idx, (button, down)) in button_states.into_iter().enumerate() {
            let has_double = bindings.contains_key(&(button, Press::Double));
            let has_long = bindings.contains_key(&(button, Press::Long));
            let short_is_hold = !has_double
                && !has_long
                && matches!(
                    bindings.get(&(button, Press::Short)),
                    Some(Binding {
                        trigger: TriggerMode::Hold,
                        ..
                    })
                );

            let events = self.machines[idx].update(
                down,
                t_us,
                long_press_us,
                double_press_us,
                has_long,
                has_double,
                short_is_hold,
            );

            for ev in events {
                self.resolve_event(button, ev, bindings, &mut actions);
            }
        }

        let has_tap_long = bindings.contains_key(&(Button::Tap, Press::Long));
        let has_tap_double = bindings.contains_key(&(Button::Tap, Press::Double));
        let tap_events = self.tap.update_events(
            sample,
            t_us,
            DEFAULT_TAP_MAX_US,
            DEFAULT_TAP_MAX_MOVE,
            long_press_us,
            double_press_us,
            has_tap_long,
            has_tap_double,
        );
        if tap_enabled {
            for ev in tap_events {
                self.resolve_event(Button::Tap, ev, bindings, &mut actions);
            }
        }

        actions
    }

    /// Returns whether a [`TriggerMode::Hold`] binding on `(button, press)` is currently held active.
    pub fn is_hold_active(&self, button: Button, press: Press) -> bool {
        self.active_holds.contains(&(button, press))
    }

    fn resolve_event(
        &mut self,
        button: Button,
        event: PressEvent,
        bindings: &Bindings,
        out: &mut Vec<Action>,
    ) {
        match event {
            PressEvent::ShortHoldStart => {
                let slot = (button, Press::Short);
                if let Some(binding) = bindings.get(&slot) {
                    self.active_holds.insert(slot);
                    out.push(hold_down_action(&binding.action));
                }
            }
            PressEvent::ShortHoldEnd => {
                let slot = (button, Press::Short);
                if self.active_holds.remove(&slot) {
                    if let Some(binding) = bindings.get(&slot) {
                        if let Some(up) = hold_up_action(&binding.action) {
                            out.push(up);
                        }
                    }
                }
            }
            PressEvent::Short => {
                let slot = (button, Press::Short);
                if let Some(binding) = bindings.get(&slot) {
                    self.fire_once_or_toggle(slot, binding, out);
                }
            }
            PressEvent::LongStart => {
                let slot = (button, Press::Long);
                if let Some(binding) = bindings.get(&slot) {
                    match binding.trigger {
                        TriggerMode::Hold => {
                            self.active_holds.insert(slot);
                            out.push(hold_down_action(&binding.action));
                        }
                        TriggerMode::Once | TriggerMode::Toggle => {
                            self.fire_once_or_toggle(slot, binding, out);
                        }
                    }
                }
            }
            PressEvent::LongEnd => {
                let slot = (button, Press::Long);
                if self.active_holds.remove(&slot) {
                    if let Some(binding) = bindings.get(&slot) {
                        if let Some(up) = hold_up_action(&binding.action) {
                            out.push(up);
                        }
                    }
                }
            }
            PressEvent::DoubleStart => {
                let slot = (button, Press::Double);
                if let Some(binding) = bindings.get(&slot) {
                    if binding.trigger == TriggerMode::Hold {
                        self.active_holds.insert(slot);
                        out.push(hold_down_action(&binding.action));
                    }
                }
            }
            PressEvent::DoubleEnd => {
                let slot = (button, Press::Double);
                if self.active_holds.remove(&slot) {
                    if let Some(binding) = bindings.get(&slot) {
                        if let Some(up) = hold_up_action(&binding.action) {
                            out.push(up);
                        }
                    }
                } else if let Some(binding) = bindings.get(&slot) {
                    self.fire_once_or_toggle(slot, binding, out);
                }
            }
        }
    }

    fn fire_once_or_toggle(
        &mut self,
        slot: (Button, Press),
        binding: &Binding,
        out: &mut Vec<Action>,
    ) {
        match binding.trigger {
            TriggerMode::Once => {
                out.push(binding.action.clone());
            }
            TriggerMode::Hold => {
                out.push(hold_down_action(&binding.action));
                if let Some(up) = hold_up_action(&binding.action) {
                    out.push(up);
                }
            }
            TriggerMode::Toggle => {
                if self.toggled_slots.remove(&slot) {
                    if let Some(up) = hold_up_action(&binding.action) {
                        out.push(up);
                    } else {
                        out.push(binding.action.clone());
                    }
                } else {
                    self.toggled_slots.insert(slot);
                    out.push(hold_down_action(&binding.action));
                }
            }
        }
    }
}
