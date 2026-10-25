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

//! //tools/pipeline/plan in Rust: the presubmit planner. Given a change, it
//! decides which pipeline units CI runs, and prints the plan (JSON, the
//! GitHub matrix, targets or text) exactly as the Go planner (main.go and
//! friends, kept as :plan-go) does: same output, same messages on stderr,
//! same exit codes.

use serde::Serialize;

pub mod cli;
mod gates;
pub mod git;
pub mod query;

pub use gates::{
    check_global_impact, classify_persona_and_operation, is_docs_only, resolve_packages,
};
pub use query::{
    build_test_rdeps_query, compute_rdeps_map, earlier_map_base, internal_query_errors, last_lines,
    load_rdeps_map, parse_graph_edges, peek_rdeps_map_commit, RdepsMap,
};

use std::time::Instant;

/// The JSON schema version of the plan.
pub const SCHEMA_VERSION: i64 = 1;

/// Where a plan's affected tests came from.
pub const PLAN_SOURCE_MAP: &str = "rdeps-map";
pub const PLAN_SOURCE_LIVE: &str = "live-query";

macro_rules! string_enum {
    ($name:ident { $($v:ident = $s:literal),* $(,)? }) => {
        #[derive(Clone, Copy, Debug, PartialEq, Eq)]
        pub enum $name { $($v),* }
        impl $name {
            pub fn as_str(&self) -> &'static str {
                match self { $($name::$v => $s),* }
            }
        }
        impl Serialize for $name {
            fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
                s.serialize_str(self.as_str())
            }
        }
    };
}

string_enum!(Persona {
    FrontendDev = "frontend-dev",
    BackendDev = "backend-dev",
    InfraEng = "infra-eng",
    PlatformAdmin = "platform-admin",
    DocsAuthor = "docs-author",
    SecurityAuditor = "security-auditor",
    FullStackDev = "fullstack-dev",
});

string_enum!(Operation {
    DocsOnly = "docs-only",
    UiFeature = "ui-feature",
    BackendApi = "backend-api",
    DatabaseMigration = "database-migration",
    InfraProvision = "infra-provision",
    DepUpdate = "dep-update",
    GlobalConfig = "global-config",
    MultiDiscipline = "multi-discipline",
});

fn is_zero(n: &i64) -> bool {
    *n == 0
}

/// One unit of the GitHub Actions matrix.
#[derive(Clone, Debug, Default, Serialize)]
pub struct MatrixEntry {
    pub name: String,
    pub package: String,
    pub runner: String,
    pub tier: String,
    pub persona: String,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub targets: Vec<String>,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub test_targets: String,
    pub target_count: usize,
    #[serde(skip_serializing_if = "is_zero")]
    pub timeout_minutes: i64,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub concurrency_group: String,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub needs: Vec<String>,
    pub is_required: bool,
}

/// The planner's output. Option fields are Go slices that may be nil
/// (null in JSON) rather than empty.
#[derive(Clone, Debug, Serialize)]
pub struct Plan {
    pub schema_version: i64,
    pub base_rev: String,
    pub head_rev: String,
    pub duration_ms: u128,
    pub changed_files: Option<Vec<String>>,
    pub affected_packages: Option<Vec<String>>,
    pub persona: Option<Persona>,
    pub operation: Option<Operation>,
    pub is_docs_only: bool,
    pub is_global_impact: bool,
    /// "I could not work out what changed, so I am running everything", as
    /// opposed to "this change genuinely affects everything".
    pub is_degraded: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub sweep_reason: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub plan_source: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub plan_source_note: String,
    pub targets: Option<Vec<String>>,
    pub target_count: usize,
    pub matrix: Vec<MatrixEntry>,
}

/// Bazel query execution, behind a trait for hermetic tests.
pub trait QueryRunner {
    /// The tests that depend on the packages, sorted.
    fn query_test_rdeps(&self, repo_root: &str, packages: &[String])
        -> Result<Vec<String>, String>;
}

/// The bit of git history the earlier-map rule needs.
pub trait RevGraph {
    fn is_ancestor(&self, older: &str, newer: &str) -> bool;
    fn commits_between(&self, older: &str, newer: &str) -> Result<i64, String>;
    fn changed_files(&self, older: &str, newer: &str) -> Result<Vec<String>, String>;
}

/// A pipeline unit as the planner uses it.
#[derive(Clone, Debug)]
pub struct UnitDef {
    pub name: String,
    pub package: String,
    pub test_targets: Vec<String>,
    pub tier: String,
    pub runner: String,
    pub persona: String,
    pub concurrency_group: String,
    pub timeout_minutes: i64,
    pub depends_on: Vec<String>,
}

fn definition_of(u: unitfile::Unit) -> UnitDef {
    UnitDef {
        concurrency_group: format!("pipeline-{}", u.name),
        name: u.name,
        package: u.package,
        test_targets: u.test_targets,
        tier: u.tier,
        runner: u.runner,
        persona: u.persona,
        timeout_minutes: u.timeout_minutes,
        depends_on: u.depends_on,
    }
}

/// The units declared in one BUILD file's text.
pub fn parse_pipeline_units_from_build(content: &str, pkg: &str) -> Result<Vec<UnitDef>, String> {
    Ok(unitfile::parse(content, pkg)?
        .into_iter()
        .map(definition_of)
        .collect())
}

fn entry(u: &UnitDef) -> MatrixEntry {
    MatrixEntry {
        name: u.name.clone(),
        package: u.package.clone(),
        runner: u.runner.clone(),
        tier: u.tier.clone(),
        persona: u.persona.clone(),
        targets: u.test_targets.clone(),
        test_targets: u.test_targets.join(" "),
        target_count: u.test_targets.len(),
        timeout_minutes: u.timeout_minutes,
        concurrency_group: u.concurrency_group.clone(),
        needs: u.depends_on.clone(),
        is_required: true,
    }
}

/// The plan engine.
pub struct Engine<'a> {
    pub repo_root: String,
    pub runner: &'a dyn QueryRunner,
    /// When set, answers the rdeps question instead of a live query. It
    /// must describe the diff base.
    pub rdeps_map: Option<RdepsMap>,
}

impl<'a> Engine<'a> {
    pub fn new(repo_root: &str, runner: &'a dyn QueryRunner) -> Engine<'a> {
        Engine {
            repo_root: repo_root.to_string(),
            runner,
            rdeps_map: None,
        }
    }

    /// Every unit declared in a BUILD file under the repo root.
    pub fn discover_units(&self) -> Result<Vec<UnitDef>, String> {
        Ok(unitfile::discover(&self.repo_root)?
            .into_iter()
            .map(definition_of)
            .collect())
    }

    /// The complete change analysis.
    pub fn compute_plan(
        &self,
        files: Vec<String>,
        base_rev: &str,
        head_rev: &str,
    ) -> Result<Plan, String> {
        let start = Instant::now();
        let mut plan = Plan {
            schema_version: SCHEMA_VERSION,
            base_rev: base_rev.to_string(),
            head_rev: head_rev.to_string(),
            duration_ms: 0,
            changed_files: if files.is_empty() {
                None
            } else {
                Some(files.clone())
            },
            affected_packages: None,
            persona: None,
            operation: None,
            is_docs_only: false,
            is_global_impact: false,
            is_degraded: false,
            sweep_reason: String::new(),
            plan_source: String::new(),
            plan_source_note: String::new(),
            targets: Some(Vec::new()),
            target_count: 0,
            matrix: Vec::new(),
        };
        let done = |mut p: Plan| -> Result<Plan, String> {
            p.duration_ms = start.elapsed().as_millis();
            Ok(p)
        };

        // 1. Docs only.
        if is_docs_only(&files) {
            plan.is_docs_only = true;
            plan.persona = Some(Persona::DocsAuthor);
            plan.operation = Some(Operation::DocsOnly);
            return done(plan);
        }

        // 2. Every declared unit.
        let all_units = self
            .discover_units()
            .map_err(|e| format!("discover pipeline units: {e}"))?;

        // 3. Global impact.
        let (global, reason) = check_global_impact(&files);
        if global {
            plan.is_global_impact = true;
            plan.sweep_reason = reason;
            plan.persona = Some(Persona::PlatformAdmin);
            plan.operation = Some(Operation::GlobalConfig);
            plan.targets = Some(vec!["//...".to_string()]);
            plan.target_count = 1;
            plan.matrix = all_units.iter().map(entry).collect();
            return done(plan);
        }

        // 4. Changed packages.
        let packages = resolve_packages(&self.repo_root, &files);
        plan.affected_packages = Some(packages.clone());
        if packages.is_empty() {
            let (p, o) = classify_persona_and_operation(&files, false, false);
            plan.persona = Some(p);
            plan.operation = Some(o);
            return done(plan);
        }

        // 5. The tests that depend on them: from the map when it covers
        // every changed package, else live.
        let mut used_map = false;
        let mut test_targets: Result<Vec<String>, String> = Ok(Vec::new());
        if let Some(m) = &self.rdeps_map {
            match m.lookup(&packages) {
                Some(t) => {
                    test_targets = Ok(t);
                    used_map = true;
                    plan.plan_source = PLAN_SOURCE_MAP.to_string();
                }
                None => {
                    plan.plan_source_note = "dependency map does not know every changed package (new package?); used the live query".to_string();
                }
            }
        }
        if !used_map {
            plan.plan_source = PLAN_SOURCE_LIVE.to_string();
            test_targets = self.runner.query_test_rdeps(&self.repo_root, &packages);
        }
        let test_targets = match test_targets {
            Ok(t) => t,
            Err(e) => {
                // Fail closed to a full sweep, marked degraded.
                plan.is_global_impact = true;
                plan.is_degraded = true;
                plan.sweep_reason = format!("query degraded: fallback to full sweep ({e})");
                plan.targets = Some(vec!["//...".to_string()]);
                plan.target_count = 1;
                plan.matrix = all_units.iter().map(entry).collect();
                let (p, o) = classify_persona_and_operation(&files, false, true);
                plan.persona = Some(p);
                plan.operation = Some(o);
                return done(plan);
            }
        };

        plan.target_count = test_targets.len();
        plan.targets = if test_targets.is_empty() {
            None
        } else {
            Some(test_targets.clone())
        };

        // 6. Persona and operation.
        let (p, o) = classify_persona_and_operation(&files, false, false);
        plan.persona = Some(p);
        plan.operation = Some(o);

        // 7. Match affected targets and packages to units.
        let target_set: std::collections::HashSet<&str> =
            test_targets.iter().map(|s| s.as_str()).collect();
        let pkg_prefixes: std::collections::HashSet<String> = packages
            .iter()
            .map(|p| {
                let c = p.strip_prefix("//").unwrap_or(p);
                c.strip_suffix(":all").unwrap_or(c).to_string()
            })
            .collect();
        for u in &all_units {
            let mut affected = pkg_prefixes.contains(&u.package);
            if used_map {
                let inside = format!("{}/", u.package);
                if pkg_prefixes.iter().any(|p| p.starts_with(&inside)) {
                    affected = true;
                }
            }
            let prefix = format!("//{}", u.package);
            for tt in &u.test_targets {
                if target_set.contains(tt.as_str()) {
                    affected = true;
                    break;
                }
                if target_set.iter().any(|at| at.starts_with(&prefix)) {
                    affected = true;
                }
            }
            if affected {
                plan.matrix.push(entry(u));
            }
        }
        done(plan)
    }
}

#[cfg(test)]
mod tests;
