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

//! Zero-dependency (std-only) UTC Timestamp and RFC3339 parser/formatter.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// A UTC timestamp with nanosecond precision.
/// A zero-initialized `Timestamp` (`is_zero == true`) corresponds to Go's `time.Time{}`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Default)]
pub struct Timestamp {
    /// False for Go's zero `time.Time{}` (`"0001-01-01T00:00:00Z"`).
    non_zero: bool,
    /// Seconds since 1970-01-01T00:00:00Z.
    secs: i64,
    /// Nanoseconds within the second `0..1_000_000_000`.
    nanos: u32,
}

impl Timestamp {
    pub const ZERO: Timestamp = Timestamp {
        non_zero: false,
        secs: 0,
        nanos: 0,
    };

    /// Swift's reference epoch: 2001-01-01T00:00:00Z (978307200 seconds after Unix epoch).
    pub const SWIFT_REFERENCE_EPOCH: Timestamp = Timestamp {
        non_zero: true,
        secs: 978_307_200,
        nanos: 0,
    };

    pub fn now() -> Self {
        match SystemTime::now().duration_since(UNIX_EPOCH) {
            Ok(d) => Self {
                non_zero: true,
                secs: d.as_secs() as i64,
                nanos: d.subsec_nanos(),
            },
            Err(_) => Self::ZERO,
        }
    }

    pub fn is_zero(&self) -> bool {
        !self.non_zero
    }

    pub fn from_unix_secs(secs: i64) -> Self {
        Self {
            non_zero: true,
            secs,
            nanos: 0,
        }
    }

    pub fn from_unix_nanos(total_nanos: i128) -> Self {
        let secs = total_nanos.div_euclid(1_000_000_000) as i64;
        let nanos = total_nanos.rem_euclid(1_000_000_000) as u32;
        Self {
            non_zero: true,
            secs,
            nanos,
        }
    }

    pub fn from_swift_timestamp(swift_secs: f64) -> Self {
        let unix_secs = 978_307_200.0 + swift_secs;
        let whole = unix_secs.floor() as i64;
        let nanos = ((unix_secs - (whole as f64)) * 1_000_000_000.0).round() as u32;
        Self {
            non_zero: true,
            secs: whole + (nanos / 1_000_000_000) as i64,
            nanos: nanos % 1_000_000_000,
        }
    }

    pub fn to_swift_seconds(&self) -> f64 {
        if !self.non_zero {
            return -978_307_200.0;
        }
        ((self.secs - 978_307_200) as f64) + (self.nanos as f64) / 1_000_000_000.0
    }

    pub fn from_ymd_hms(year: i32, month: u32, day: u32, hour: u32, min: u32, sec: u32) -> Self {
        Self::from_ymd_hms_nano(year, month, day, hour, min, sec, 0)
    }

    pub fn from_ymd_hms_nano(
        year: i32,
        month: u32,
        day: u32,
        hour: u32,
        min: u32,
        sec: u32,
        nanos: u32,
    ) -> Self {
        let days = days_from_civil(year, month, day);
        let secs = days * 86_400 + (hour as i64) * 3_600 + (min as i64) * 60 + (sec as i64);
        Self {
            non_zero: true,
            secs,
            nanos,
        }
    }

    pub fn unix_secs(&self) -> i64 {
        self.secs
    }

    pub fn unix_seconds(&self) -> i64 {
        self.secs
    }

    pub fn unix_nanos(&self) -> i128 {
        (self.secs as i128) * 1_000_000_000 + (self.nanos as i128)
    }

    pub fn add_duration(&self, d: Duration) -> Self {
        if !self.non_zero {
            return *self;
        }
        Self::from_unix_nanos(self.unix_nanos() + (d.as_nanos() as i128))
    }

    pub fn add(&self, d: Duration) -> Self {
        self.add_duration(d)
    }

    pub fn sub_duration(&self, d: Duration) -> Self {
        if !self.non_zero {
            return *self;
        }
        Self::from_unix_nanos(self.unix_nanos() - (d.as_nanos() as i128))
    }

    pub fn sub(&self, d: Duration) -> Self {
        self.sub_duration(d)
    }

    pub fn duration_since(&self, earlier: Timestamp) -> Duration {
        if !self.non_zero || !earlier.non_zero {
            return Duration::ZERO;
        }
        let diff = self.unix_nanos() - earlier.unix_nanos();
        if diff <= 0 {
            Duration::ZERO
        } else {
            Duration::from_nanos(diff as u64)
        }
    }

    pub fn signed_millis_since(&self, earlier: Timestamp) -> i64 {
        if !self.non_zero || !earlier.non_zero {
            return 0;
        }
        ((self.unix_nanos() - earlier.unix_nanos()) / 1_000_000) as i64
    }

    pub fn after(&self, other: Timestamp) -> bool {
        self > &other
    }

    pub fn ymd_hms(&self) -> (i32, u32, u32, u32, u32, u32) {
        if !self.non_zero {
            return (1, 1, 1, 0, 0, 0);
        }
        let days = self.secs.div_euclid(86_400);
        let rem = self.secs.rem_euclid(86_400) as u32;
        let hour = rem / 3_600;
        let min = (rem % 3_600) / 60;
        let sec = rem % 60;
        let (y, m, d) = civil_from_days(days);
        (y, m, d, hour, min, sec)
    }

    pub fn hour(&self) -> u32 {
        self.ymd_hms().3
    }

    pub fn minute(&self) -> u32 {
        self.ymd_hms().4
    }

    pub fn to_rfc3339_nano(&self) -> String {
        self.to_rfc3339()
    }

    pub fn to_rfc3339(&self) -> String {
        if !self.non_zero {
            return "0001-01-01T00:00:00Z".to_string();
        }
        let (y, m, d, hh, mm, ss) = self.ymd_hms();
        if self.nanos == 0 {
            format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", y, m, d, hh, mm, ss)
        } else {
            let mut frac = format!("{:09}", self.nanos);
            while frac.ends_with('0') {
                frac.pop();
            }
            format!(
                "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}.{}Z",
                y, m, d, hh, mm, ss, frac
            )
        }
    }

    pub fn parse_rfc3339(s: &str) -> Result<Self, String> {
        let s = s.trim();
        if s == "0001-01-01T00:00:00Z" {
            return Ok(Self::ZERO);
        }
        if s.len() < 20 {
            return Err(format!("timestamp too short: {}", s));
        }
        let bytes = s.as_bytes();
        if bytes[4] != b'-'
            || bytes[7] != b'-'
            || (bytes[10] != b'T' && bytes[10] != b't' && bytes[10] != b' ')
            || bytes[13] != b':'
            || bytes[16] != b':'
        {
            return Err(format!("invalid RFC3339 format: {}", s));
        }
        let year: i32 = s[0..4].parse().map_err(|_| "invalid year".to_string())?;
        let month: u32 = s[5..7].parse().map_err(|_| "invalid month".to_string())?;
        let day: u32 = s[8..10].parse().map_err(|_| "invalid day".to_string())?;
        let hour: u32 = s[11..13].parse().map_err(|_| "invalid hour".to_string())?;
        let min: u32 = s[14..16]
            .parse()
            .map_err(|_| "invalid minute".to_string())?;
        let sec: u32 = s[17..19]
            .parse()
            .map_err(|_| "invalid second".to_string())?;
        if !(1..=12).contains(&month)
            || !(1..=31).contains(&day)
            || hour > 23
            || min > 59
            || sec > 60
        {
            return Err(format!("out-of-range date/time fields in {}", s));
        }

        let mut rest = &s[19..];
        let mut nanos: u32 = 0;
        if let Some(after_dot) = rest.strip_prefix('.') {
            let digits_len = after_dot.bytes().take_while(|b| b.is_ascii_digit()).count();
            if digits_len == 0 {
                return Err(format!("empty fractional seconds in {}", s));
            }
            let frac_str = &after_dot[..digits_len];
            let mut n: u32 = 0;
            let mut mult: u32 = 100_000_000;
            for b in frac_str.bytes().take(9) {
                n += ((b - b'0') as u32) * mult;
                mult /= 10;
            }
            nanos = n;
            rest = &after_dot[digits_len..];
        }

        let offset_secs: i64 = if rest == "Z" || rest == "z" {
            0
        } else if (rest.starts_with('+') || rest.starts_with('-'))
            && rest.len() == 6
            && rest.as_bytes()[3] == b':'
        {
            let sign: i64 = if rest.starts_with('+') { 1 } else { -1 };
            let oh: i64 = rest[1..3]
                .parse()
                .map_err(|_| "invalid tz hour".to_string())?;
            let om: i64 = rest[4..6]
                .parse()
                .map_err(|_| "invalid tz minute".to_string())?;
            sign * (oh * 3600 + om * 60)
        } else {
            return Err(format!("invalid timezone offset '{}' in {}", rest, s));
        };

        let base = Self::from_ymd_hms_nano(year, month, day, hour, min, sec, nanos);
        Ok(Self {
            non_zero: true,
            secs: base.secs - offset_secs,
            nanos: base.nanos,
        })
    }
}

/// Howard Hinnant's algorithm: converts proleptic Gregorian date to days since 1970-01-01.
fn days_from_civil(y: i32, m: u32, d: u32) -> i64 {
    let y = (y as i64) - if m <= 2 { 1 } else { 0 };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = (y - era * 400) as u64;
    let m = m as u64;
    let d = d as u64;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + (doe as i64) - 719_468
}

/// Howard Hinnant's algorithm: converts days since 1970-01-01 to proleptic Gregorian (year, month, day).
fn civil_from_days(z: i64) -> (i32, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = (yoe as i64) + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = y + if m <= 2 { 1 } else { 0 };
    (y as i32, m as u32, d as u32)
}
