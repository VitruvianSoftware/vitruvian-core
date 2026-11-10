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

//! 8-slice radial menu slot selection.

use crate::bindings::Action;
use serde::{Deserialize, Serialize};
use std::f32::consts::PI;

/// Number of slices in the radial menu.
pub const RADIAL_SLOT_COUNT: usize = 8;

/// Configuration for a single slice of the 8-slot radial menu.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct RadialSlot {
    /// Display label for the slice.
    pub label: String,
    /// Design-token color name or hex string for the slice.
    pub color: String,
    /// Action executed when the user releases the radial menu button on this slice.
    pub action: Option<Action>,
}

impl Default for RadialSlot {
    fn default() -> Self {
        Self {
            label: String::new(),
            color: String::from("surface"),
            action: None,
        }
    }
}

/// Maps a 2D cursor offset `(dx, dy)` from the radial menu origin into one of 8 clockwise slots (`0..=7`).
///
/// Coordinate convention matches screen space (`dx > 0` = right, `dy < 0` = up):
/// - Slot 0: Up (`dx = 0, dy < 0`), covering `[-22.5°, +22.5°)`
/// - Slot 1: Up-Right (`dx > 0, dy < 0`), covering `[+22.5°, +67.5°)`
/// - Slot 2: Right (`dx > 0, dy = 0`), covering `[+67.5°, +112.5°)`
/// - Slot 3: Down-Right (`dx > 0, dy > 0`), covering `[+112.5°, +157.5°)`
/// - Slot 4: Down (`dx = 0, dy > 0`), covering `[+157.5°, +202.5°)`
/// - Slot 5: Down-Left (`dx < 0, dy > 0`), covering `[+202.5°, +247.5°)`
/// - Slot 6: Left (`dx < 0, dy = 0`), covering `[+247.5°, +292.5°)`
/// - Slot 7: Up-Left (`dx < 0, dy < 0`), covering `[+292.5°, +337.5°)`
///
/// Returns `None` if `sqrt(dx² + dy²) <= dead_radius` or if coordinates are non-finite.
pub fn slot_for(dx: f32, dy: f32, dead_radius: f32) -> Option<u8> {
    let dist = (dx * dx + dy * dy).sqrt();
    if !dist.is_finite() || dist <= dead_radius.max(0.0) {
        return None;
    }

    // Angle in radians with 0 at Up (dx = 0, dy = -1), increasing clockwise.
    let angle = dx.atan2(-dy).rem_euclid(2.0 * PI);
    let slice = PI / 4.0;
    let half_slice = PI / 8.0;
    let slot = (((angle + half_slice) / slice).floor() as u8) % 8;
    Some(slot)
}
