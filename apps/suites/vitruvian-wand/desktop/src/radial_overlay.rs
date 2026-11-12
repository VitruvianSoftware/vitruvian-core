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

//! 8-slot radial menu overlay state machine and Wayland/cursor viewport positioning glue.

use vitruvian_wand_core::{Action, RadialSlot, slot_for};

/// Fixed width and height of the radial menu child viewport in points (`280×280`).
pub const RADIAL_VIEWPORT_SIZE: f32 = 280.0;

/// Direction names for each of the 8 radial slots (`0 = Up`, clockwise).
pub const RADIAL_SLOT_DIRECTIONS: [&str; 8] = [
    "Up",
    "Up-Right",
    "Right",
    "Down-Right",
    "Down",
    "Down-Left",
    "Left",
    "Up-Left",
];

/// Returns `true` when `wayland_display` is set and non-empty (indicating a Wayland compositor).
pub fn is_wayland_display(wayland_display: Option<&str>) -> bool {
    matches!(wayland_display, Some(s) if !s.trim().is_empty())
}

/// Returns `true` when running under a Wayland compositor (`WAYLAND_DISPLAY` is set).
pub fn is_wayland_session() -> bool {
    let val = std::env::var("WAYLAND_DISPLAY").ok();
    is_wayland_display(val.as_deref())
}

/// Computes the top-left window coordinates `(x, y)` for the `280×280` radial overlay:
/// - On macOS and X11 (`!is_wayland`), centres the overlay on `cursor_pos`.
/// - On Wayland (`is_wayland`), centres the overlay on `screen_size` because Wayland does not
///   allow clients to position surfaces at global cursor coordinates.
pub fn compute_radial_viewport_origin(
    is_wayland: bool,
    cursor_pos: Option<(f32, f32)>,
    screen_size: (f32, f32),
) -> (f32, f32) {
    let half = RADIAL_VIEWPORT_SIZE * 0.5;
    if !is_wayland && let Some((cx, cy)) = cursor_pos {
        return (cx - half, cy - half);
    }
    let (sw, sh) = screen_size;
    (
        (sw - RADIAL_VIEWPORT_SIZE) * 0.5,
        (sh - RADIAL_VIEWPORT_SIZE) * 0.5,
    )
}

/// Stateful controller for the desktop 8-slot radial menu overlay.
#[derive(Debug, Clone)]
pub struct RadialOverlayController {
    open: bool,
    dx: f32,
    dy: f32,
    dead_radius: f32,
    selected_slot: Option<u8>,
}

impl Default for RadialOverlayController {
    fn default() -> Self {
        Self::new(15.0)
    }
}

impl RadialOverlayController {
    /// Creates a new [`RadialOverlayController`] with `dead_radius`.
    pub const fn new(dead_radius: f32) -> Self {
        Self {
            open: false,
            dx: 0.0,
            dy: 0.0,
            dead_radius,
            selected_slot: None,
        }
    }

    /// Updates the dead-centre radius threshold.
    pub fn set_dead_radius(&mut self, dead_radius: f32) {
        self.dead_radius = dead_radius;
        if self.open {
            self.selected_slot = slot_for(self.dx, self.dy, self.dead_radius);
        }
    }

    /// Opens the radial overlay at `(0, 0)` offset.
    pub fn open(&mut self) {
        self.open = true;
        self.dx = 0.0;
        self.dy = 0.0;
        self.selected_slot = None;
    }

    /// Feeds a relative pointer movement `(move_dx, move_dy)` while the radial menu is open,
    /// updating `selected_slot` via [`vitruvian_wand_core::slot_for`].
    pub fn feed_move(&mut self, move_dx: f32, move_dy: f32) -> Option<u8> {
        if !self.open {
            return None;
        }
        self.dx += move_dx;
        self.dy += move_dy;
        self.selected_slot = slot_for(self.dx, self.dy, self.dead_radius);
        self.selected_slot
    }

    /// Closes the radial menu on release and returns the selected slot's configured [`Action`], if any.
    pub fn release(&mut self, slots: &[RadialSlot]) -> Option<Action> {
        if !self.open {
            return None;
        }
        self.open = false;
        let idx = self.selected_slot.take()?;
        slots.get(idx as usize).and_then(|s| s.action.clone())
    }

    /// Returns `true` if the radial overlay is currently open.
    pub const fn is_open(&self) -> bool {
        self.open
    }

    /// Returns the accumulated `(dx, dy)` offset from the radial menu origin.
    pub const fn offset(&self) -> (f32, f32) {
        (self.dx, self.dy)
    }

    /// Returns the currently highlighted slot (`0..=7`), or `None` when inside the deadzone.
    pub const fn selected_slot(&self) -> Option<u8> {
        self.selected_slot
    }
}
