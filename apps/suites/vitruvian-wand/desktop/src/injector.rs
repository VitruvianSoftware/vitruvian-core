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

//! Platform output [`Injector`] trait, device-independent pixel scaling constant,
//! fractional scroll accumulator, and deterministic [`FakeInjector`] for testing.

use std::fmt;
use vitruvian_wand_core::Action;

/// Pixel scale multiplier converting `vitruvian_wand_core`'s device-independent `Action::Move { dx, dy }`
/// units into desktop screen pixels.
///
/// Calibration math:
/// - A full touchpad swipe spans normalized coordinates `0.0 -> 1.0` (`raw_dx = 1.0`).
/// - With default `touch_sensitivity = 400.0`, one full swipe emits `400.0` engine units,
///   and two full swipes emit `2 * 400.0 = 800.0` engine units.
/// - Multiplying by `PIXEL_SCALE = 1.8` yields `800.0 * 1.8 = 1440.0` pixels, crossing a
///   1440 px wide display in two full touchpad swipes.
pub const PIXEL_SCALE: f32 = 1.8;

/// Base pixel multiplier per unit of `Action::Scroll { dx, dy }` on desktop.
pub const SCROLL_PIXEL_STEP: f32 = 24.0;

/// Converts device-independent `(dx, dy)` movement deltas into scaled desktop pixel deltas.
#[inline]
pub const fn scale_move_delta(dx: f32, dy: f32) -> (f32, f32) {
    (dx * PIXEL_SCALE, dy * PIXEL_SCALE)
}

/// Converts normalized scroll deltas `(dx, dy)` into pixel scroll deltas for a single step.
#[inline]
pub const fn scale_scroll_pixels(dx: f32, dy: f32) -> (i32, i32) {
    (
        (dx * SCROLL_PIXEL_STEP).round() as i32,
        (dy * SCROLL_PIXEL_STEP).round() as i32,
    )
}

/// Converts normalized scroll deltas `(dx, dy)` into integer pixel scroll deltas while carrying
/// the sub-pixel fractional remainder `(rem_x, rem_y)` across packets (matching Linux move accumulation).
#[inline]
pub fn scale_scroll_pixels_accum(dx: f32, dy: f32, rem_x: &mut f32, rem_y: &mut f32) -> (i32, i32) {
    let total_x = dx * SCROLL_PIXEL_STEP + *rem_x;
    let total_y = dy * SCROLL_PIXEL_STEP + *rem_y;
    let ix = total_x.trunc() as i32;
    let iy = total_y.trunc() as i32;
    *rem_x = total_x - ix as f32;
    *rem_y = total_y - iy as f32;
    (ix, iy)
}

/// Error returned when an [`Injector`] cannot emit an operating-system input event.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InjectorError(pub String);

impl fmt::Display for InjectorError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for InjectorError {}

/// Trait for injecting [`Action`]s into the host operating system.
pub trait Injector: Send {
    /// Applies a single [`Action`] to the host OS input subsystem.
    fn apply(&mut self, action: &Action) -> Result<(), InjectorError>;

    /// Applies a slice of [`Action`]s in order, stopping on the first error.
    fn apply_all(&mut self, actions: &[Action]) -> Result<(), InjectorError> {
        for action in actions {
            self.apply(action)?;
        }
        Ok(())
    }

    /// Updates the `screen_width_px` setting used on Linux to convert `Action::PointTo` deltas
    /// into relative pixel movements.
    fn set_screen_width_px(&mut self, _width_px: u64) {}
}

/// Deterministic test double that records every applied [`Action`], scaled pixel moves,
/// and accumulated integer pixel scrolls.
#[derive(Debug, Clone, Default)]
pub struct FakeInjector {
    /// All actions passed to [`Injector::apply`] in exact order.
    pub actions: Vec<Action>,
    /// Scaled `(px_dx, px_dy)` deltas recorded for every `Action::Move`.
    pub pixel_moves: Vec<(f32, f32)>,
    /// Non-zero integer `(px_dx, px_dy)` scroll events emitted after remainder accumulation.
    pub pixel_scrolls: Vec<(i32, i32)>,
    /// Carried sub-pixel horizontal scroll remainder.
    pub scroll_rem_x: f32,
    /// Carried sub-pixel vertical scroll remainder.
    pub scroll_rem_y: f32,
    /// Whether the primary mouse button is currently held down.
    pub left_button_down: bool,
}

impl FakeInjector {
    /// Creates an empty [`FakeInjector`].
    pub fn new() -> Self {
        Self::default()
    }

    /// Clears all recorded actions and resets button and remainder state.
    pub fn clear(&mut self) {
        self.actions.clear();
        self.pixel_moves.clear();
        self.pixel_scrolls.clear();
        self.scroll_rem_x = 0.0;
        self.scroll_rem_y = 0.0;
        self.left_button_down = false;
    }
}

impl Injector for FakeInjector {
    fn apply(&mut self, action: &Action) -> Result<(), InjectorError> {
        match action {
            Action::Move { dx, dy } => {
                self.pixel_moves.push(scale_move_delta(*dx, *dy));
            }
            Action::Scroll { dx, dy } => {
                let (sx, sy) = scale_scroll_pixels_accum(
                    *dx,
                    *dy,
                    &mut self.scroll_rem_x,
                    &mut self.scroll_rem_y,
                );
                if sx != 0 || sy != 0 {
                    self.pixel_scrolls.push((sx, sy));
                }
            }
            Action::MouseDown => {
                self.left_button_down = true;
            }
            Action::MouseUp => {
                self.left_button_down = false;
            }
            _ => {}
        }
        self.actions.push(action.clone());
        Ok(())
    }
}

/// Canonical list of named keyboard keys supported in `KeyChord::key`.
pub const CANONICAL_KEY_NAMES: &[&str] = &[
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
    "x",
    "y",
    "z",
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    "Return",
    "Space",
    "Tab",
    "Backspace",
    "Delete",
    "Escape",
    "Up",
    "Down",
    "Left",
    "Right",
    "Home",
    "End",
    "PageUp",
    "PageDown",
    "F1",
    "F2",
    "F3",
    "F4",
    "F5",
    "F6",
    "F7",
    "F8",
    "F9",
    "F10",
    "F11",
    "F12",
    "-",
    "=",
    "[",
    "]",
    "\\",
    ";",
    "'",
    ",",
    ".",
    "/",
    "`",
];
