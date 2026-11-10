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

//! Stationary gyroscope bias calibration.

use crate::protocol::daydream::{Sample, Vec3};
use std::fmt;

/// Default number of stationary samples collected during calibration.
pub const DEFAULT_CALIBRATION_SAMPLES: usize = 30;

/// Default maximum motion threshold (rad/s) allowed while calibrating on a flat surface.
pub const DEFAULT_MOTION_THRESHOLD: f32 = 0.25;

/// Error returned when stationary gyroscope calibration fails.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CalibrationError {
    /// No samples were provided to calibrate from.
    EmptySamples,
    /// Controller motion exceeded the allowed stationary threshold.
    TooMuchMotion,
}

pub use CalibrationError::TooMuchMotion;

impl fmt::Display for CalibrationError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::EmptySamples => write!(f, "cannot calibrate from zero samples"),
            Self::TooMuchMotion => {
                write!(
                    f,
                    "too much motion during calibration; keep the controller flat"
                )
            }
        }
    }
}

impl std::error::Error for CalibrationError {}

/// Computes the mean gyroscope bias vector from `samples` if the controller stayed still.
///
/// Returns `Err(CalibrationError::TooMuchMotion)` if any sample's angular speed norm or
/// deviation from the sample mean exceeds `threshold` (in rad/s).
pub fn calibrate(samples: &[Sample], threshold: f32) -> Result<Vec3, CalibrationError> {
    if samples.is_empty() {
        return Err(CalibrationError::EmptySamples);
    }
    let gyros: Vec<Vec3> = samples.iter().map(|s| s.gyro).collect();
    calibrate_gyro(&gyros, threshold)
}

/// Computes the mean gyroscope bias vector from raw gyro readings `gyros` (in rad/s).
pub fn calibrate_gyro(gyros: &[Vec3], threshold: f32) -> Result<Vec3, CalibrationError> {
    if gyros.is_empty() {
        return Err(CalibrationError::EmptySamples);
    }

    let n = gyros.len() as f32;
    let mut sum = Vec3::default();
    for g in gyros {
        if g.norm() > threshold {
            return Err(CalibrationError::TooMuchMotion);
        }
        sum.x += g.x;
        sum.y += g.y;
        sum.z += g.z;
    }

    let mean = Vec3 {
        x: sum.x / n,
        y: sum.y / n,
        z: sum.z / n,
    };

    for g in gyros {
        let diff = Vec3 {
            x: g.x - mean.x,
            y: g.y - mean.y,
            z: g.z - mean.z,
        };
        if diff.norm() > threshold {
            return Err(CalibrationError::TooMuchMotion);
        }
    }

    Ok(mean)
}

/// Streaming accumulator that collects `target_samples` and computes the stationary gyro bias.
#[derive(Debug, Clone)]
pub struct Calibrator {
    target_samples: usize,
    threshold: f32,
    samples: Vec<Vec3>,
}

impl Calibrator {
    /// Creates a new [`Calibrator`] that collects `target_samples` with motion limit `threshold`.
    pub fn new(target_samples: usize, threshold: f32) -> Self {
        let cap = target_samples.max(1);
        Self {
            target_samples: cap,
            threshold,
            samples: Vec::with_capacity(cap),
        }
    }

    /// Feeds one [`Sample`] into the calibrator.
    ///
    /// Returns `None` while still collecting samples, or `Some(Result<Vec3, CalibrationError>)`
    /// once `target_samples` have been accumulated.
    pub fn push(&mut self, sample: &Sample) -> Option<Result<Vec3, CalibrationError>> {
        self.samples.push(sample.gyro);
        if self.samples.len() >= self.target_samples {
            Some(calibrate_gyro(&self.samples, self.threshold))
        } else {
            None
        }
    }
}
