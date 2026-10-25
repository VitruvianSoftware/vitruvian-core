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

//! Times in UTC, to the second, as the catalog writes them
//! (`2026-11-02T10:00:00Z`): `datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ")`
//! with _strptime's own regular expression (one-digit months and hours
//! pass, `t` and `z` pass, as its IGNORECASE has them) and datetime's range
//! checks; `strftime` of the same format; and the clock.

use crate::pyre;

/// Seconds since 1970-01-01T00:00:00Z.
pub type Stamp = i64;

fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
}

fn days_in_month(y: i64, m: i64) -> i64 {
    match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        _ => {
            if (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 {
                29
            } else {
                28
            }
        }
    }
}

fn digits(text: &str) -> i64 {
    text.chars().fold(0, |n, c| {
        n * 10 + crate::pystr::decimal_value(c).unwrap_or(0) as i64
    })
}

/// `datetime.strptime(text, "%Y-%m-%dT%H:%M:%SZ")` in UTC, or None where it
/// raises ValueError.
pub fn parse(text: &str) -> Option<Stamp> {
    let re = pyre::fixed(concat!(
        r"(?P<Y>\d\d\d\d)-(?P<m>1[0-2]|0[1-9]|[1-9])-",
        r"(?P<d>3[01]|[12]\d|0[1-9]|[1-9]| [1-9])[Tt]",
        r"(?P<H>2[0-3]|[0-1]\d|\d):(?P<M>[0-5]\d|\d):(?P<S>6[0-1]|[0-5]\d|\d)[Zz]"
    ));
    let m = re.match_start(text)?;
    if m.end() != text.chars().count() {
        return None; // unconverted data remains
    }
    let field = |name: &str| digits(&m.named(name).unwrap_or_default());
    let (y, mo, d) = (field("Y"), field("m"), field("d"));
    let (h, mi, s) = (field("H"), field("M"), field("S"));
    if !(1..=9999).contains(&y) || d > days_in_month(y, mo) || s > 59 {
        return None;
    }
    Some(days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + s)
}

/// `stamp.strftime("%Y-%m-%dT%H:%M:%SZ")`.
pub fn format(stamp: Stamp) -> String {
    let days = stamp.div_euclid(86400);
    let secs = stamp.rem_euclid(86400);
    let (y, m, d) = civil_from_days(days);
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        y,
        m,
        d,
        secs / 3600,
        secs % 3600 / 60,
        secs % 60
    )
}

/// `datetime.now(timezone.utc).replace(microsecond=0)`.
pub fn now() -> Stamp {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_what_strptime_reads() {
        let t = parse("2026-11-02T10:00:00Z").unwrap();
        assert_eq!(format(t), "2026-11-02T10:00:00Z");
        assert_eq!(parse("2026-1-2T3:4:5Z"), parse("2026-01-02T03:04:05Z"));
        assert_eq!(parse("2026-01-02t03:04:05z"), parse("2026-01-02T03:04:05Z"));
        assert_eq!(
            parse("2024-02-29T00:00:00Z").map(format).unwrap(),
            "2024-02-29T00:00:00Z"
        );
        assert_eq!(parse("2026-02-29T00:00:00Z"), None);
        assert_eq!(parse("2026-01-01T00:00:60Z"), None);
        assert_eq!(parse("2026-01-01T00:00:00"), None);
        assert_eq!(parse("2026-01-01T00:00:00Zx"), None);
        assert_eq!(parse("2026-01-01 00:00:00Z"), None);
        assert_eq!(parse("0000-01-01T00:00:00Z"), None);
        assert_eq!(parse("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(
            format(parse("2030-01-02T03:04:05Z").unwrap() + 1),
            "2030-01-02T03:04:06Z"
        );
    }
}
