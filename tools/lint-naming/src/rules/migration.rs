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

//! rules/migration.py: rename risk and backwards-compatibility checks.

use crate::violation::{Severity, Violation};
use std::collections::HashMap;
use std::path::Path;

/// MigrationRiskLevel.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RiskLevel {
    Low,
    Medium,
    High,
}

impl RiskLevel {
    pub fn as_str(self) -> &'static str {
        match self {
            RiskLevel::Low => "LOW",
            RiskLevel::Medium => "MEDIUM",
            RiskLevel::High => "HIGH",
        }
    }
}

/// Paths with a high blast radius (HIGH_RISK_PREFIXES).
pub const HIGH_RISK_PREFIXES: &[&str] = &[
    ".github/workflows",
    "gitops",
    "packages/design-system",
    "tabula/extension/public",
    "tabula/web/prisma",
];

/// MEDIUM_RISK_PREFIXES.
pub const MEDIUM_RISK_PREFIXES: &[&str] =
    &["infrastructure/pulumi", "pulumi/library", "devx", "tools"];

/// assess_rename_risk. The target path does not enter into it.
pub fn assess_rename_risk(source_path: &str, _target_path: &str) -> RiskLevel {
    let norm = source_path.replace('\\', "/");
    if ["_test.go", "_test.sh", ".test.ts", ".spec.tsx"]
        .iter()
        .any(|s| norm.ends_with(s))
    {
        return RiskLevel::Low;
    }
    if HIGH_RISK_PREFIXES.iter().any(|p| norm.starts_with(p)) {
        return RiskLevel::High;
    }
    if MEDIUM_RISK_PREFIXES.iter().any(|p| norm.starts_with(p)) {
        return RiskLevel::Medium;
    }
    RiskLevel::Low
}

/// validate_alias_compatibility.
pub fn validate_alias_compatibility(
    old_target: &str,
    new_target: &str,
    alias_map: &HashMap<String, String>,
) -> Vec<Violation> {
    let mut violations = Vec::new();
    if alias_map.get(old_target).map(String::as_str) != Some(new_target) {
        violations.push(Violation::new(
            "MIG001",
            old_target,
            None,
            format!(
                "Missing backwards-compatible alias for renamed target '{}' -> '{}'.",
                old_target, new_target
            ),
            Severity::Warning,
            None,
        ));
    }
    violations
}

/// validate_symlink_alias: `os.path.islink(old_path)`.
pub fn validate_symlink_alias(old_path: &str, _expected_target: &str) -> Vec<Violation> {
    let mut violations = Vec::new();
    let is_link = std::fs::symlink_metadata(Path::new(old_path))
        .map(|m| m.file_type().is_symlink())
        .unwrap_or(false);
    if !is_link {
        violations.push(Violation::new(
            "MIG002",
            old_path,
            None,
            format!("Compatibility symlink '{}' does not exist.", old_path),
            Severity::Error,
            None,
        ));
    }
    violations
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn risk_levels() {
        assert_eq!(
            assess_rename_risk("tools/ci/test_runner_test.sh", ""),
            RiskLevel::Low
        );
        assert_eq!(
            assess_rename_risk("tools/pulumi/create_app.sh", ""),
            RiskLevel::Medium
        );
        assert_eq!(
            assess_rename_risk(".github/workflows/deploy.yaml", ""),
            RiskLevel::High
        );
        assert_eq!(
            assess_rename_risk("gitops\\apps\\app.yaml", ""),
            RiskLevel::High
        );
        assert_eq!(assess_rename_risk("", ""), RiskLevel::Low);
    }

    #[test]
    fn aliases_and_symlinks() {
        let mut m = HashMap::new();
        m.insert("//a:old".to_string(), "//a:new".to_string());
        assert!(validate_alias_compatibility("//a:old", "//a:new", &m).is_empty());
        let v = validate_alias_compatibility("//a:old", "//a:other", &m);
        assert_eq!(
            (v[0].rule_id.as_str(), v[0].severity),
            ("MIG001", Severity::Warning)
        );
        assert_eq!(
            validate_symlink_alias("/nonexistent/path", "/t")[0].rule_id,
            "MIG002"
        );
    }
}
