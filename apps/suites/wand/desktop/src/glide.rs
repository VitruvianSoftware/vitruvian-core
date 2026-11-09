// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files (the "Software"), to deal in the Software
// without restriction, including without limitation the rights to use, copy, modify,
// merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be included in all copies
// or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
// INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
// PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
// CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
// OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

//! Pure linear cursor interpolation (`Glide`) between discrete `PointTo` updates on Desktop.
//!
//! BLE notifications from the Daydream controller arrive roughly every ~29 ms median (p90 58 ms,
//! max 180 ms). Jumping directly on each packet stutters on 60–120 Hz displays. [`Glide`]
//! interpolates linearly from the current rendered position to each new target over an EWMA
//! (`α = 0.2`) of measured inter-arrival intervals (starting at 30 ms, clamped to 8–60 ms),
//! driven at 125 Hz (8 ms ticks) while a glide is in progress.

/// Tick interval while a glide is active (`8 ms` = `8_000 µs`, 125 Hz).
pub const GLIDE_TICK_US: u64 = 8_000;

/// Minimum glide duration (`8 ms` = `8_000 µs`).
pub const GLIDE_MIN_DURATION_US: u64 = 8_000;

/// Maximum glide duration (`60 ms` = `60_000 µs`).
pub const GLIDE_MAX_DURATION_US: u64 = 60_000;

/// Initial EWMA glide duration before inter-packet intervals are measured (`30 ms` = `30_000 µs`).
pub const GLIDE_DEFAULT_DURATION_US: u64 = 30_000;

/// Exponentially weighted moving average factor (`α = 0.2`) for `PointTo` arrival intervals.
pub const GLIDE_EWMA_ALPHA: f32 = 0.2;

#[inline]
fn lerp_clamped(a: f32, b: f32, t: f32) -> f32 {
    let lo = a.min(b);
    let hi = a.max(b);
    (a + (b - a) * t).clamp(lo, hi)
}

/// Pure, unit-testable linear interpolator in `PointTo` units (screen widths from centre).
#[derive(Debug, Clone, PartialEq)]
pub struct Glide {
    rendered: (f32, f32),
    from: (f32, f32),
    to: (f32, f32),
    start_us: u64,
    duration_us: u64,
    ewma_us: f32,
    last_arrival_us: Option<u64>,
    last_emitted: Option<(f32, f32)>,
    active: bool,
}

impl Default for Glide {
    fn default() -> Self {
        Self::new()
    }
}

impl Glide {
    /// Creates a new [`Glide`] in its reset state (first `PointTo` snaps immediately, initial
    /// EWMA duration = `30 ms`).
    pub const fn new() -> Self {
        Self {
            rendered: (0.0, 0.0),
            from: (0.0, 0.0),
            to: (0.0, 0.0),
            start_us: 0,
            duration_us: GLIDE_DEFAULT_DURATION_US,
            ewma_us: GLIDE_DEFAULT_DURATION_US as f32,
            last_arrival_us: None,
            last_emitted: None,
            active: false,
        }
    }

    /// Resets the glide state (used on `Recenter`, `ToggleGyro`, `ReleaseAll`, or disconnect)
    /// so the first `PointTo` after a reset lands immediately without gliding.
    pub fn reset(&mut self) {
        *self = Self::new();
    }

    /// Returns the most recently rendered `(x, y)` position in `PointTo` units.
    pub const fn rendered(&self) -> (f32, f32) {
        self.rendered
    }

    /// Returns the start position `(x, y)` of the current glide segment.
    pub const fn from(&self) -> (f32, f32) {
        self.from
    }

    /// Returns the target position `(x, y)` of the current glide segment.
    pub const fn target(&self) -> (f32, f32) {
        self.to
    }

    /// Returns the start timestamp (in µs) of the current glide segment.
    pub const fn start_us(&self) -> u64 {
        self.start_us
    }

    /// Returns the current glide duration (in µs), clamped to `8_000..=60_000`.
    pub const fn duration_us(&self) -> u64 {
        self.duration_us
    }

    /// Returns `true` while a glide from `from` to `to` is still in progress.
    pub const fn is_active(&self) -> bool {
        self.active
    }

    /// Evaluates the linearly interpolated `(x, y)` position at `now_us` without mutating state.
    ///
    /// Moves linearly from `from` to `to` over `duration_us`, then holds at `to`.
    /// Never overshoots and never extrapolates.
    pub fn position_at(&self, now_us: u64) -> (f32, f32) {
        if !self.active || self.duration_us == 0 {
            return self.to;
        }
        if now_us <= self.start_us {
            return self.from;
        }
        let elapsed_us = now_us - self.start_us;
        if elapsed_us >= self.duration_us {
            return self.to;
        }
        let t = (elapsed_us as f32 / self.duration_us as f32).clamp(0.0, 1.0);
        (
            lerp_clamped(self.from.0, self.to.0, t),
            lerp_clamped(self.from.1, self.to.1, t),
        )
    }

    /// Feeds a new engine `PointTo` target at timestamp `now_us` (in µs).
    ///
    /// - On the first `PointTo` after creation or [`Glide::reset`], snaps immediately to `target`
    ///   and returns `Some(target)`.
    /// - On subsequent `PointTo` updates, sets `from` to the current rendered position at `now_us`,
    ///   `to` to `target`, `start` to `now_us`, updates `duration_us` using an EWMA (`α = 0.2`) of
    ///   measured inter-arrival intervals clamped to `8..=60 ms`, and returns `None` (subsequent
    ///   125 Hz [`Glide::step`] ticks emit the interpolated positions).
    pub fn on_point_to(&mut self, target: (f32, f32), now_us: u64) -> Option<(f32, f32)> {
        let Some(prev_us) = self.last_arrival_us else {
            self.rendered = target;
            self.from = target;
            self.to = target;
            self.start_us = now_us;
            self.duration_us = GLIDE_DEFAULT_DURATION_US;
            self.ewma_us = GLIDE_DEFAULT_DURATION_US as f32;
            self.last_arrival_us = Some(now_us);
            self.last_emitted = Some(target);
            self.active = false;
            return Some(target);
        };

        let cur = self.position_at(now_us);
        let rem_us = if self.active {
            self.start_us
                .saturating_add(self.duration_us)
                .saturating_sub(now_us)
        } else {
            0
        };
        self.rendered = cur;

        if now_us > prev_us {
            let interval_us = (now_us - prev_us) as f32;
            self.ewma_us =
                (GLIDE_EWMA_ALPHA * interval_us + (1.0 - GLIDE_EWMA_ALPHA) * self.ewma_us)
                    .clamp(GLIDE_MIN_DURATION_US as f32, GLIDE_MAX_DURATION_US as f32);
            let ewma_dur = (self.ewma_us.round() as u64)
                .clamp(GLIDE_MIN_DURATION_US, GLIDE_MAX_DURATION_US);
            self.duration_us = ewma_dur
                .max(rem_us)
                .clamp(GLIDE_MIN_DURATION_US, GLIDE_MAX_DURATION_US);
        }
        self.last_arrival_us = Some(now_us);
        self.from = cur;
        self.to = target;
        self.start_us = now_us;
        self.active = self.from != self.to;
        None
    }

    /// Advances the glide to `now_us` (in µs) and returns `Some(rendered)` iff a glide is active
    /// and the rendered position changed since the last emitted position.
    pub fn step(&mut self, now_us: u64) -> Option<(f32, f32)> {
        if !self.active {
            return None;
        }
        let pos = self.position_at(now_us);
        self.rendered = pos;
        if now_us.saturating_sub(self.start_us) >= self.duration_us {
            self.active = false;
        }
        if self.last_emitted != Some(pos) {
            self.last_emitted = Some(pos);
            Some(pos)
        } else {
            None
        }
    }
}
