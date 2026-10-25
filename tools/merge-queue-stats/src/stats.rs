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

//! merge_queue_stats.py's counting and its report: the same functions under
//! the same names, on the same JSON the script reads from GitHub.

use std::cmp::Ordering;

use crate::json::Value;
use crate::pyerr::{self, Crash};
use crate::pystr;
use crate::pytime;

pub const QUEUE_BOT: &str = "github-merge-queue";

/// A datetime: microseconds since the epoch, in UTC when `aware`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Time {
    pub micros: i64,
    pub aware: bool,
}

impl Time {
    pub fn utc(micros: i64) -> Time {
        Time {
            micros,
            aware: true,
        }
    }

    /// Python's comparison, which refuses to mix naive and aware.
    pub fn compare(&self, other: &Time) -> Result<Ordering, Crash> {
        if self.aware != other.aware {
            return Err(Crash::new(
                "TypeError",
                "can't compare offset-naive and offset-aware datetimes",
            ));
        }
        Ok(self.micros.cmp(&other.micros))
    }

    fn le(&self, other: &Time) -> Result<bool, Crash> {
        Ok(self.compare(other)? != Ordering::Greater)
    }

    fn lt(&self, other: &Time) -> Result<bool, Crash> {
        Ok(self.compare(other)? == Ordering::Less)
    }
}

/// `parse_time`: `fromisoformat(value.replace("Z", "+00:00"))`.
pub fn parse_time(value: &Value) -> Result<Time, Crash> {
    let s = pyerr::as_str(value, "replace")?.replace('Z', "+00:00");
    let p = pytime::fromisoformat(&s).map_err(|m| Crash::new("ValueError", m))?;
    Ok(match p.offset {
        Some(off) => Time::utc(p.wall - off),
        None => Time {
            micros: p.wall,
            aware: false,
        },
    })
}

/// `day`: a date or datetime given on the command line, as UTC whatever
/// offset it carries (`.replace(tzinfo=utc)` replaces, it does not convert).
pub fn day(value: &str) -> Result<Time, String> {
    pytime::fromisoformat(value).map(|p| Time::utc(p.wall))
}

/// `percentile`: nearest rank; None for no values.
pub fn percentile(values: &[f64], fraction: f64) -> Option<f64> {
    if values.is_empty() {
        return None;
    }
    let mut ordered = values.to_vec();
    ordered.sort_by(|a, b| a.partial_cmp(b).unwrap_or(Ordering::Equal));
    let raw = pystr::round_half_even(fraction * ordered.len() as f64 + 0.5 - 1e-9);
    let rank = (raw as i64).max(1) as usize;
    Some(ordered[rank.min(ordered.len()) - 1])
}

/// `minutes`.
pub fn minutes(value: Option<f64>) -> String {
    match value {
        None => "\u{2013}".into(),
        Some(v) => format!("{} min", pystr::format_fixed(v, 1)),
    }
}

fn nodes(pr: &Value) -> Result<Vec<Value>, Crash> {
    pyerr::iterate(&pyerr::index(&pyerr::index(pr, "timelineItems")?, "nodes")?)
}

fn typename_is(e: &Value, name: &str) -> Result<bool, Crash> {
    Ok(matches!(pyerr::get_or(e, "__typename", Value::Null)?, Value::Str(s) if s == name))
}

/// `queue_times`: (last-entry minutes, first-entry minutes).
pub fn queue_times(
    pulls: &[Value],
    since: Time,
    until: Time,
) -> Result<(Vec<f64>, Vec<f64>), Crash> {
    let (mut last, mut first) = (Vec::new(), Vec::new());
    for pr in pulls {
        if !pyerr::get_or(pr, "mergedAt", Value::Null)?.truthy() {
            continue;
        }
        let merged = parse_time(&pyerr::index(pr, "mergedAt")?)?;
        if !(since.le(&merged)? && merged.lt(&until)?) {
            continue;
        }
        let mut added: Vec<Time> = Vec::new();
        for e in nodes(pr)? {
            if !typename_is(&e, "AddedToMergeQueueEvent")? {
                continue;
            }
            let t = parse_time(&pyerr::index(&e, "createdAt")?)?;
            if t.le(&merged)? {
                added.push(t);
            }
        }
        if added.is_empty() {
            continue;
        }
        // Every one compared against merged, so all are aware.
        added.sort_by_key(|t| t.micros);
        let mins = |t: &Time| pytime::total_seconds(merged.micros - t.micros) / 60.0;
        last.push(mins(added.last().unwrap()));
        first.push(mins(&added[0]));
    }
    Ok((last, first))
}

/// Counts in first-seen order, as a dict keeps them.
#[derive(Debug, Default, PartialEq)]
pub struct Counts(pub Vec<(String, usize)>);

impl Counts {
    fn add(&mut self, key: &str) {
        match self.0.iter_mut().find(|(k, _)| k == key) {
            Some(slot) => slot.1 += 1,
            None => self.0.push((key.to_string(), 1)),
        }
    }

    pub fn total(&self) -> usize {
        self.0.iter().map(|(_, n)| n).sum()
    }

    /// `sorted(items, key=lambda kv: -kv[1])`: stable.
    pub fn by_count(&self) -> Vec<(String, usize)> {
        let mut items = self.0.clone();
        items.sort_by(|a, b| b.1.cmp(&a.1));
        items
    }
}

/// `ejections`: removals by the queue itself in the window, by reason.
pub fn ejections(pulls: &[Value], since: Time, until: Time) -> Result<Counts, Crash> {
    let mut counts = Counts::default();
    for pr in pulls {
        for e in nodes(pr)? {
            if !typename_is(&e, "RemovedFromMergeQueueEvent")? {
                continue;
            }
            let t = parse_time(&pyerr::index(&e, "createdAt")?)?;
            if !(since.le(&t)? && t.lt(&until)?) {
                continue;
            }
            let actor = pyerr::get_or(&e, "actor", Value::Null)?;
            let actor = if actor.truthy() {
                actor
            } else {
                Value::Obj(vec![])
            };
            let login = pyerr::get_or(&actor, "login", Value::Null)?;
            let is_bot = login.truthy() && matches!(&login, Value::Str(s) if s == QUEUE_BOT);
            if !is_bot {
                continue;
            }
            let reason = pyerr::get_or(&e, "reason", Value::Null)?;
            let reason = if reason.truthy() {
                reason
            } else {
                Value::Str("unknown".into())
            };
            let stripped = pystr::strip(pyerr::as_str(&reason, "strip")?).to_string();
            let reason = if stripped.is_empty() {
                "unknown".to_string()
            } else {
                stripped
            };
            if reason.to_lowercase() == "merged" {
                continue;
            }
            counts.add(&reason);
        }
    }
    Ok(counts)
}

/// A JSON value as a dict key: Python's equal values (1, 1.0, True) are one
/// key, shown as the first one seen.
#[derive(Debug, PartialEq)]
enum Key {
    Null,
    Num(f64),
    Str(String),
}

fn key_of(v: &Value) -> Result<Key, Crash> {
    match v {
        Value::Null => Ok(Key::Null),
        Value::Str(s) => Ok(Key::Str(s.clone())),
        Value::Bool(_) | Value::Int(_) | Value::Float(_) => {
            Ok(Key::Num(v.as_f64().unwrap_or(f64::NAN)))
        }
        Value::Arr(_) | Value::Obj(_) => Err(Crash::new(
            "TypeError",
            format!("unhashable type: '{}'", v.type_name()),
        )),
    }
}

/// `failed_runs`: failed push runs, counted by workflow name.
pub fn failed_runs(runs: &[Value]) -> Result<Vec<(String, usize)>, Crash> {
    let mut keys: Vec<(Key, String, usize)> = Vec::new();
    for run in runs {
        let conclusion = pyerr::get_or(run, "conclusion", Value::Null)?;
        if !matches!(&conclusion, Value::Str(s) if s == "failure" || s == "timed_out") {
            continue;
        }
        let name = pyerr::index(run, "name")?;
        let key = key_of(&name)?;
        let found = keys.iter_mut().find(|(k, _, _)| *k == key);
        match found {
            Some(slot) => slot.2 += 1,
            None => keys.push((key, name.py_str(), 1)),
        }
    }
    Ok(keys.into_iter().map(|(_, shown, n)| (shown, n)).collect())
}

/// `report`: the Markdown the tool prints.
pub fn report(
    repo: &str,
    since: Time,
    until: Time,
    pulls: &[Value],
    runs: &[Value],
    reverts: &[String],
) -> Result<String, Crash> {
    let (last, first) = queue_times(pulls, since, until)?;
    let eject = ejections(pulls, since, until)?;
    let failed = failed_runs(runs)?;
    let days = (pytime::total_seconds(until.micros - since.micros) / 86400.0).max(1e-9);
    let stamp = |t: Time| pytime::format(t.micros, "%Y-%m-%d %H:%M");
    let mut lines = vec![
        format!(
            "### Merge queue, {}, {} to {} UTC",
            repo,
            stamp(since),
            stamp(until)
        ),
        String::new(),
        "| Speed | |".into(),
        "|---|---|".into(),
        format!(
            "| PRs merged through the queue | {} ({}/day) |",
            last.len(),
            pystr::format_fixed(last.len() as f64 / days, 1)
        ),
        format!(
            "| Last entry \u{2192} merged | median {}, p90 {} |",
            minutes(percentile(&last, 0.5)),
            minutes(percentile(&last, 0.9))
        ),
        format!(
            "| First entry \u{2192} merged (with retries) | median {}, p90 {} |",
            minutes(percentile(&first, 0.5)),
            minutes(percentile(&first, 0.9))
        ),
        String::new(),
        format!("**Ejections by the queue:** {}", eject.total()),
        String::new(),
    ];
    let ej = eject.by_count();
    if ej.is_empty() {
        lines.push("- none".into());
    }
    for (reason, n) in ej {
        lines.push(format!("- {}: {}", reason, n));
    }
    let failed_total: usize = failed.iter().map(|(_, n)| n).sum();
    lines.push(String::new());
    lines.push(format!(
        "**Breakage on main:** {} failed push run(s), {} revert(s)",
        failed_total,
        reverts.len()
    ));
    lines.push(String::new());
    let mut sorted = failed.clone();
    sorted.sort_by(|a, b| b.1.cmp(&a.1));
    if sorted.is_empty() {
        lines.push("- no failed push runs".into());
    }
    for (name, n) in sorted {
        lines.push(format!("- {}: {}", name, n));
    }
    for r in reverts {
        lines.push(format!("- revert: {}", r));
    }
    Ok(lines.join("\n") + "\n")
}

#[cfg(test)]
mod tests {
    //! The cases in merge_queue_stats_test.py, on the same timelines.
    use super::*;
    use crate::json::loads;

    fn since() -> Time {
        day("2026-10-05").unwrap()
    }

    fn until() -> Time {
        day("2026-10-19").unwrap()
    }

    fn s(v: &str) -> Value {
        Value::Str(v.into())
    }

    fn added(at: &str) -> Value {
        Value::Obj(vec![
            ("__typename".into(), s("AddedToMergeQueueEvent")),
            ("createdAt".into(), s(at)),
        ])
    }

    fn removed(at: &str, reason: &str, who: &str) -> Value {
        Value::Obj(vec![
            ("__typename".into(), s("RemovedFromMergeQueueEvent")),
            ("createdAt".into(), s(at)),
            ("reason".into(), s(reason)),
            ("actor".into(), Value::Obj(vec![("login".into(), s(who))])),
        ])
    }

    fn pr(merged: Option<&str>, events: Vec<Value>) -> Value {
        Value::Obj(vec![
            ("number".into(), Value::Int("1".into())),
            ("mergedAt".into(), merged.map(s).unwrap_or(Value::Null)),
            (
                "timelineItems".into(),
                Value::Obj(vec![("nodes".into(), Value::Arr(events))]),
            ),
        ])
    }

    #[test]
    fn test_last_and_first_entry() {
        let retried = pr(
            Some("2026-10-10T01:00:00Z"),
            vec![
                added("2026-10-10T00:00:00Z"),
                removed("2026-10-10T00:20:00Z", "failed_checks", QUEUE_BOT),
                added("2026-10-10T00:50:00Z"),
                removed("2026-10-10T01:00:00Z", "merged", QUEUE_BOT),
            ],
        );
        let (last, first) = queue_times(&[retried], since(), until()).unwrap();
        assert_eq!(last, vec![10.0]);
        assert_eq!(first, vec![60.0]);
    }

    #[test]
    fn test_skips_unmerged_outside_window_and_never_queued() {
        let pulls = vec![
            pr(None, vec![added("2026-10-10T00:00:00Z")]),
            pr(
                Some("2026-10-20T00:00:00Z"),
                vec![added("2026-10-19T23:00:00Z")],
            ),
            pr(Some("2026-10-10T00:00:00Z"), vec![]),
            pr(
                Some("2026-10-10T00:05:00Z"),
                vec![added("2026-10-10T00:10:00Z")],
            ),
        ];
        assert_eq!(
            queue_times(&pulls, since(), until()).unwrap(),
            (vec![], vec![])
        );
    }

    #[test]
    fn test_counts_the_queue_bot_only_and_never_merged() {
        let pulls = vec![pr(
            Some("2026-10-10T01:00:00Z"),
            vec![
                removed("2026-10-10T00:20:00Z", "failed_checks", QUEUE_BOT),
                removed("2026-10-10T00:30:00Z", "checks_timed_out", QUEUE_BOT),
                removed("2026-10-10T00:40:00Z", "failed_checks", QUEUE_BOT),
                removed("2026-10-10T00:45:00Z", "dequeued", "james"),
                removed("2026-10-10T01:00:00Z", "merged", QUEUE_BOT),
                removed("2026-10-20T00:00:00Z", "failed_checks", QUEUE_BOT),
            ],
        )];
        assert_eq!(
            ejections(&pulls, since(), until()).unwrap(),
            Counts(vec![
                ("failed_checks".into(), 2),
                ("checks_timed_out".into(), 1)
            ])
        );
    }

    #[test]
    fn test_shape() {
        let pulls = vec![pr(
            Some("2026-10-10T00:10:00Z"),
            vec![added("2026-10-10T00:00:00Z")],
        )];
        let runs = loads(
            r#"[{"name": "CI", "conclusion": "failure"},
                {"name": "CI", "conclusion": "timed_out"},
                {"name": "Presubmit", "conclusion": "success"}]"#,
        )
        .unwrap();
        let Value::Arr(runs) = runs else { panic!() };
        let out = report(
            "o/r",
            since(),
            until(),
            &pulls,
            &runs,
            &["Revert \"x\"".into()],
        )
        .unwrap();
        assert!(out.contains("| PRs merged through the queue | 1 (0.1/day) |"));
        assert!(out.contains("median 10.0 min, p90 10.0 min"));
        assert!(out.contains("**Ejections by the queue:** 0"));
        assert!(out.contains("**Breakage on main:** 2 failed push run(s), 1 revert(s)"));
        assert!(out.contains("- CI: 2"));
        assert!(!out.contains("Presubmit"));
    }

    #[test]
    fn test_percentile() {
        assert_eq!(percentile(&[], 0.5), None);
        assert_eq!(percentile(&[3.0, 1.0, 2.0], 0.5), Some(2.0));
        let ten: Vec<f64> = (1..=10).map(|n| n as f64).collect();
        assert_eq!(percentile(&ten, 0.9), Some(9.0));
    }

    #[test]
    fn naive_times_and_offsets() {
        // A timestamp with no offset cannot be compared with the window.
        let naive = pr(Some("2026-10-10T00:10:00"), vec![]);
        assert_eq!(
            queue_times(&[naive], since(), until()).unwrap_err().class,
            "TypeError"
        );
        // An offset converts: 05:10+05:00 is 00:10 UTC, ten minutes after.
        let offset = pr(
            Some("2026-10-10T05:10:00+05:00"),
            vec![added("2026-10-10T00:00:00Z")],
        );
        assert_eq!(
            queue_times(&[offset], since(), until()).unwrap().0,
            vec![10.0]
        );
        // --since with an offset keeps the wall time, as replace() does.
        assert_eq!(
            day("2026-10-05T12:00+05:00").unwrap(),
            day("2026-10-05T12:00").unwrap()
        );
    }
}
