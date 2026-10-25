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

//! Python 3.12's `datetime.fromisoformat`, ported from its C implementation
//! (`_datetimemodule.c`): the same formats (calendar and ISO-week dates,
//! basic and extended times, `.` or `,` fractions, any one character as the
//! separator) and the same refusals. Times are microseconds from
//! 1970-01-01T00:00 on the proleptic Gregorian calendar.

pub const MICROS_PER_DAY: i64 = 86_400_000_000;

/// A parsed `fromisoformat` result: the wall-clock time and, if the string
/// had one, its UTC offset.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Parsed {
    pub wall: i64,
    pub offset: Option<i64>,
}

fn is_leap(y: i64) -> bool {
    y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
}

fn days_in_month(y: i64, m: i64) -> i64 {
    match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        _ => {
            if is_leap(y) {
                29
            } else {
                28
            }
        }
    }
}

/// CPython's ymd_to_ord: 0001-01-01 is day 1.
fn ymd_to_ord(y: i64, m: i64, d: i64) -> i64 {
    let yy = y - 1;
    let before_year = yy * 365 + yy / 4 - yy / 100 + yy / 400;
    let mut before_month = 0;
    for mm in 1..m {
        before_month += days_in_month(y, mm);
    }
    before_year + before_month + d
}

fn ord_to_ymd(ordinal: i64) -> (i64, i64, i64) {
    // Days from 1970-01-01 via the civil algorithm (exact for any ordinal).
    civil_from_days(ordinal - ymd_to_ord(1970, 1, 1))
}

/// Howard Hinnant's days_from_civil: days from 1970-01-01.
pub fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

pub fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
}

fn iso_to_ymd(iso_year: i64, week: i64, day: i64) -> Option<(i64, i64, i64)> {
    if week <= 0 || week >= 53 {
        let mut out_of_range = true;
        if week == 53 {
            let first_weekday = (ymd_to_ord(iso_year, 1, 1) + 6) % 7;
            if first_weekday == 3 || (first_weekday == 2 && is_leap(iso_year)) {
                out_of_range = false;
            }
        }
        if out_of_range {
            return None;
        }
    }
    if day <= 0 || day >= 8 {
        return None;
    }
    let first_day = ymd_to_ord(iso_year, 1, 1);
    let first_weekday = (first_day + 6) % 7;
    let mut week1_monday = first_day - first_weekday;
    if first_weekday > 3 {
        week1_monday += 7;
    }
    Some(ord_to_ymd(week1_monday + (week - 1) * 7 + day - 1))
}

/// A string the C parser walks, reading NUL past its end as C would.
struct Cs<'a>(&'a [char]);

impl<'a> Cs<'a> {
    fn at(&self, i: usize) -> char {
        self.0.get(i).copied().unwrap_or('\0')
    }
}

fn digits(s: &Cs, p: usize, n: usize) -> Option<(i64, usize)> {
    let mut v = 0i64;
    for i in 0..n {
        let c = s.at(p + i);
        if !c.is_ascii_digit() {
            return None;
        }
        v = v * 10 + (c as i64 - '0' as i64);
    }
    Some((v, p + n))
}

fn find_separator(s: &Cs, len: usize) -> Option<usize> {
    if len == 7 {
        return Some(7);
    }
    if s.at(4) == '-' {
        if s.at(5) == 'W' {
            if len < 8 {
                return None;
            }
            if len > 8 && s.at(8) == '-' {
                if len == 9 {
                    return None;
                }
                if len > 10 && s.at(10).is_ascii_digit() {
                    return Some(8);
                }
                return Some(10);
            }
            return Some(8);
        }
        return Some(10);
    }
    if s.at(4) == 'W' {
        let mut idx = 7;
        while idx < len && s.at(idx).is_ascii_digit() {
            idx += 1;
        }
        if idx < 9 {
            return Some(idx);
        }
        return Some(if idx % 2 == 0 { 7 } else { 8 });
    }
    Some(8)
}

fn parse_date(s: &Cs, len: usize) -> Option<(i64, i64, i64)> {
    let (year, mut p) = digits(s, 0, 4)?;
    let sep = s.at(p) == '-';
    if sep {
        p += 1;
    }
    if s.at(p) == 'W' {
        p += 1;
        let (week, q) = digits(s, p, 2)?;
        p = q;
        let mut day = 1;
        if p < len {
            if sep {
                if s.at(p) != '-' {
                    return None;
                }
                p += 1;
            }
            day = digits(s, p, 1)?.0;
        }
        return iso_to_ymd(year, week, day);
    }
    let (month, q) = digits(s, p, 2)?;
    p = q;
    if sep {
        if s.at(p) != '-' {
            return None;
        }
        p += 1;
    }
    let (day, _) = digits(s, p, 2)?;
    Some((year, month, day))
}

/// Hours, minutes, seconds, microseconds.
type Hms = (i64, i64, i64, i64);

/// parse_hh_mm_ss_ff over s[p..end]; Ok(more) where `more` is the C
/// function's 1 ("something follows").
fn parse_hms(s: &Cs, p0: usize, end: usize) -> Result<(Hms, bool), ()> {
    let mut vals = [0i64; 3];
    let mut p = p0;
    let mut has_sep = true;
    let mut fraction = false;
    for (i, val) in vals.iter_mut().enumerate() {
        let (v, q) = digits(s, p, 2).ok_or(())?;
        *val = v;
        p = q;
        let c = s.at(p);
        p += 1;
        if i == 0 {
            has_sep = c == ':';
        }
        if p >= end {
            return Ok(((vals[0], vals[1], vals[2], 0), c != '\0'));
        } else if has_sep && c == ':' {
            continue;
        } else if c == '.' || c == ',' {
            fraction = true;
            break;
        } else if !has_sep {
            p -= 1;
        } else {
            return Err(());
        }
    }
    let _ = fraction;
    let remains = end - p;
    let to_parse = remains.min(6);
    let (mut us, mut q) = digits(s, p, to_parse).ok_or(())?;
    if to_parse < 6 {
        // C multiplies by correction[to_parse - 1]; to_parse is never 0 here
        // for a valid string, and 0 digits parse as 0 either way.
        us *= 10i64.pow((6 - to_parse) as u32);
    }
    while s.at(q).is_ascii_digit() {
        q += 1;
    }
    Ok(((vals[0], vals[1], vals[2], us), s.at(q) != '\0'))
}

/// `datetime.fromisoformat(text)`; Err is its ValueError.
pub fn fromisoformat(text: &str) -> Result<Parsed, String> {
    let invalid = || format!("Invalid isoformat string: {}", crate::pystr::repr_str(text));
    let chars: Vec<char> = text.chars().collect();
    let len = chars.len();
    if len < 7 || chars.iter().any(|c| *c == '\0') {
        return Err(invalid());
    }
    let s = Cs(&chars);
    let sep = find_separator(&s, len).ok_or_else(invalid)?;
    let (year, month, day) = parse_date(&s, sep).ok_or_else(invalid)?;
    let (mut h, mut mi, mut sec, mut us) = (0, 0, 0, 0);
    let mut offset = None;
    if len > sep {
        // The rest of the string, after the one-character separator.
        let rest: Vec<char> = chars[sep + 1..].to_vec();
        let t = Cs(&rest);
        let tlen = rest.len();
        let mut tz = 0;
        while tz < tlen && !matches!(t.at(tz), 'Z' | '+' | '-') {
            tz += 1;
        }
        if tlen == 0 {
            tz = 0;
        }
        let ((hh, mm, ss, ff), more) = parse_hms(&t, 0, tz).map_err(|_| invalid())?;
        h = hh;
        mi = mm;
        sec = ss;
        us = ff;
        if tz == tlen {
            if more {
                return Err(invalid());
            }
        } else if t.at(tz) == 'Z' {
            if t.at(tz + 1) != '\0' {
                return Err(invalid());
            }
            offset = Some(0);
        } else {
            let sign = if t.at(tz) == '-' { -1 } else { 1 };
            let ((th, tm, ts, tus), more) = parse_hms(&t, tz + 1, tlen).map_err(|_| invalid())?;
            if more {
                return Err(invalid());
            }
            let off = sign * ((th * 3600 + tm * 60 + ts) * 1_000_000 + tus);
            if off.abs() >= MICROS_PER_DAY {
                return Err("offset must be a timedelta strictly between -timedelta(hours=24) and timedelta(hours=24).".into());
            }
            offset = Some(off);
        }
    }
    if !(1..=9999).contains(&year) {
        return Err(format!("year {} is out of range", year));
    }
    if !(1..=12).contains(&month) {
        return Err("month must be in 1..12".into());
    }
    if day < 1 || day > days_in_month(year, month) {
        return Err("day is out of range for month".into());
    }
    if h > 23 {
        return Err("hour must be in 0..23".into());
    }
    if mi > 59 {
        return Err("minute must be in 0..59".into());
    }
    if sec > 59 {
        return Err("second must be in 0..59".into());
    }
    let wall = days_from_civil(year, month, day) * MICROS_PER_DAY
        + ((h * 60 + mi) * 60 + sec) * 1_000_000
        + us;
    Ok(Parsed { wall, offset })
}

/// `timedelta.total_seconds()` for a difference in microseconds: Python
/// divides the integer by 10**6 with one correct rounding, as parsing the
/// exact decimal does.
pub fn total_seconds(micros: i64) -> f64 {
    let neg = micros < 0;
    let m = (micros as i128).abs();
    let text = format!(
        "{}{}.{:06}",
        if neg { "-" } else { "" },
        m / 1_000_000,
        m % 1_000_000
    );
    text.parse().unwrap()
}

/// strftime for UTC microseconds: `%Y-%m-%d %H:%M` and friends. Years
/// print with four digits, as on macOS (glibc would not pad years below
/// 1000; the tool never sees those).
pub fn format(micros: i64, pattern: &str) -> String {
    let days = micros.div_euclid(MICROS_PER_DAY);
    let rem = micros.rem_euclid(MICROS_PER_DAY) / 1_000_000;
    let (y, m, d) = civil_from_days(days);
    let (hh, mm, ss) = (rem / 3600, rem / 60 % 60, rem % 60);
    let mut out = String::new();
    let mut it = pattern.chars();
    while let Some(c) = it.next() {
        if c != '%' {
            out.push(c);
            continue;
        }
        match it.next() {
            Some('Y') => out.push_str(&format!("{:04}", y)),
            Some('m') => out.push_str(&format!("{:02}", m)),
            Some('d') => out.push_str(&format!("{:02}", d)),
            Some('H') => out.push_str(&format!("{:02}", hh)),
            Some('M') => out.push_str(&format!("{:02}", mm)),
            Some('S') => out.push_str(&format!("{:02}", ss)),
            Some(other) => {
                out.push('%');
                out.push(other);
            }
            None => out.push('%'),
        }
    }
    out
}

/// Now, in UTC microseconds, whole seconds (`.replace(microsecond=0)`).
pub fn now() -> i64 {
    let d = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    d.as_secs() as i64 * 1_000_000
}

#[cfg(test)]
mod tests {
    use super::*;

    fn iso(s: &str) -> Option<String> {
        fromisoformat(s).ok().map(|p| {
            let base = format(p.wall, "%Y-%m-%dT%H:%M:%S");
            let us = p.wall.rem_euclid(1_000_000);
            let mut out = if us != 0 {
                format!("{}.{:06}", base, us)
            } else {
                base
            };
            if let Some(o) = p.offset {
                out.push_str(&format!("{:+}", o));
            }
            out
        })
    }

    #[test]
    fn formats_python_accepts() {
        assert_eq!(iso("2026-10-05").as_deref(), Some("2026-10-05T00:00:00"));
        assert_eq!(iso("20261005").as_deref(), Some("2026-10-05T00:00:00"));
        assert_eq!(iso("2026-W41").as_deref(), Some("2026-10-05T00:00:00"));
        assert_eq!(iso("2026W411").as_deref(), Some("2026-10-05T00:00:00"));
        assert_eq!(iso("2026-W53").as_deref(), Some("2026-12-28T00:00:00"));
        assert_eq!(iso("2020-W53-7").as_deref(), Some("2021-01-03T00:00:00"));
        assert_eq!(
            iso("2026-10-05T1230").as_deref(),
            Some("2026-10-05T12:30:00")
        );
        assert_eq!(
            iso("2026-10-05T12.5").as_deref(),
            Some("2026-10-05T12:00:00.500000")
        );
        assert_eq!(
            iso("2026-10-05T12:30:15:00").as_deref(),
            Some("2026-10-05T12:30:15")
        );
        assert_eq!(
            iso("2026-10-05\u{e9}12:30").as_deref(),
            Some("2026-10-05T12:30:00")
        );
        assert_eq!(
            iso("2026-10-05T12:30Z").as_deref(),
            Some("2026-10-05T12:30:00+0")
        );
        assert_eq!(
            iso("2026-10-05T12-05").as_deref(),
            Some("2026-10-05T12:00:00-18000000000")
        );
        assert_eq!(iso("2026-W41-1-12").as_deref(), Some("2026-10-05T12:00:00"));
        assert_eq!(
            iso("2026-10-05T12:30:15,123456789Z").as_deref(),
            Some("2026-10-05T12:30:15.123456+0")
        );
    }

    #[test]
    fn formats_python_refuses() {
        for s in [
            "2026-10-5",
            "2026-1005",
            "202610-05",
            "2026-10-05T",
            "2026-10-05T12:3",
            "2026-10-05T12:30:15.",
            "2026-10-05T1230150",
            "2026-W41-112",
            "2026W4112",
            "9999-W53",
            "2025-W53",
            "2026-W00",
            "2026-10-05T24:00",
            "2026-02-30",
            "2026-10-05T12:30+24:00",
            "2026-10-05Z",
            "2026-10-05T12:30z",
            " 2026-10-05",
            "2026-10-05\u{e9}\u{e9}12:30",
            "9999-W52-7",
            "2026-10-05T12:30+05:30Z",
        ] {
            assert_eq!(iso(s), None, "{}", s);
        }
    }

    #[test]
    fn seconds_and_format() {
        assert_eq!(total_seconds(600_000_000), 600.0);
        assert_eq!(total_seconds(-1), -1e-6);
        assert_eq!(format(0, "%Y-%m-%d %H:%M"), "1970-01-01 00:00");
        let p = fromisoformat("2026-10-19").unwrap();
        assert_eq!(format(p.wall, "%Y-%m-%dT%H:%M:%SZ"), "2026-10-19T00:00:00Z");
    }
}
