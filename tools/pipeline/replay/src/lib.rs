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

//! Replay recent main commits through the presubmit planner twice -- once with
//! the dependency map as it is (the rule from #4815) and once with its
//! `unit_packages` removed (the rule before it) -- and count how often each
//! Mac unit would wake under each. See README.md.

use std::collections::BTreeMap;

use plan::{is_mac_runner, Engine, QueryRunner, RdepsMap};

/// Refuses every live query. A commit whose plan needs one is skipped rather
/// than planned from a slow, differently-timed Bazel query.
pub struct NoLiveQuery;

impl QueryRunner for NoLiveQuery {
    fn query_test_rdeps(&self, _: &str, _: &[String]) -> Result<Vec<String>, String> {
        Err("live query not available in replay".to_string())
    }
}

/// What one commit does under both rules.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome {
    /// Both rules planned from the map. Sorted Mac unit names each wakes.
    Planned { old: Vec<String>, new: Vec<String> },
    /// The map did not cover the change (or it touched everything): not comparable.
    Skipped(String),
}

/// The map with the #4815 field removed: the planner then takes its older,
/// broader rule for Mac units.
pub fn without_unit_packages(m: &RdepsMap) -> RdepsMap {
    let mut o = m.clone();
    o.unit_packages = None;
    o
}

fn mac_units(p: &plan::Plan) -> Vec<String> {
    let mut v: Vec<String> = p
        .matrix
        .iter()
        .filter(|e| is_mac_runner(&e.runner))
        .map(|e| e.name.clone())
        .collect();
    v.sort();
    v
}

/// Plans `files` under both rules.
pub fn replay_one(repo_root: &str, map: &RdepsMap, files: Vec<String>) -> Outcome {
    let runner = NoLiveQuery;
    let run = |m: &RdepsMap| -> Result<plan::Plan, String> {
        let mut e = Engine::new(repo_root, &runner);
        e.rdeps_map = Some(m.clone());
        e.compute_plan(files.clone(), "replay-base", "replay-head")
    };
    let new = match run(map) {
        Ok(p) => p,
        Err(e) => return Outcome::Skipped(e),
    };
    let old = match run(&without_unit_packages(map)) {
        Ok(p) => p,
        Err(e) => return Outcome::Skipped(e),
    };
    if new.is_degraded || old.is_degraded {
        return Outcome::Skipped("needs a live query".to_string());
    }
    if new.is_global_impact || old.is_global_impact {
        return Outcome::Skipped("touches everything".to_string());
    }
    Outcome::Planned {
        old: mac_units(&old),
        new: mac_units(&new),
    }
}

/// Per Mac unit: commits it wakes under the old and the new rule.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Tally {
    pub planned: usize,
    pub skipped: usize,
    pub per_unit: BTreeMap<String, (usize, usize)>,
    /// Commits where the new rule woke a unit the old rule did not. The new
    /// rule is meant to be narrower; any entry here is a bug to look at.
    pub new_only: Vec<String>,
}

pub fn tally(results: &[(String, Outcome)]) -> Tally {
    let mut t = Tally::default();
    for (id, r) in results {
        match r {
            Outcome::Skipped(_) => t.skipped += 1,
            Outcome::Planned { old, new } => {
                t.planned += 1;
                for u in old {
                    t.per_unit.entry(u.clone()).or_default().0 += 1;
                }
                for u in new {
                    t.per_unit.entry(u.clone()).or_default().1 += 1;
                    if !old.contains(u) {
                        t.new_only.push(format!("{id}: {u}"));
                    }
                }
            }
        }
    }
    t
}

/// `git diff --name-only` output to a file list.
pub fn parse_files(out: &str) -> Vec<String> {
    out.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(String::from)
        .collect()
}

pub fn render(t: &Tally) -> String {
    let mut s = format!(
        "{} commits compared, {} skipped (needed a live query or touched everything)\n\n",
        t.planned, t.skipped
    );
    s += &format!(
        "{:<34}{:>8}{:>8}{:>10}\n",
        "Mac unit", "old", "new", "change"
    );
    let (mut so, mut sn) = (0, 0);
    for (u, (o, n)) in &t.per_unit {
        so += o;
        sn += n;
        s += &format!("{:<34}{:>8}{:>8}{:>10}\n", u, o, n, delta(*o, *n));
    }
    s += &format!(
        "{:<34}{:>8}{:>8}{:>10}\n",
        "ALL Mac unit wakes",
        so,
        sn,
        delta(so, sn)
    );
    if !t.new_only.is_empty() {
        s += "\nWARNING: the new rule woke units the old rule did not:\n";
        for x in &t.new_only {
            s += &format!("  {x}\n");
        }
    }
    s
}

fn delta(o: usize, n: usize) -> String {
    if o == 0 {
        return "-".to_string();
    }
    format!("{:+.0}%", (n as f64 - o as f64) * 100.0 / o as f64)
}

#[cfg(test)]
mod tests;
