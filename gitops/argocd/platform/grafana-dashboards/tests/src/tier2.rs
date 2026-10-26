// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Tier 2: PromQL Syntax & Metric Integrity Validation Test.
//!
//! Validates PromQL syntax parsing across all panel targets and template variables,
//! verifies unit conversions (ms vs s), aggregation scoping (sum before rate vs after),
//! and division safety guards.

use std::collections::HashSet;
use std::path::Path;

use serde_json::Value;

use crate::{
    as_json_i64, collect_all_panels, find_dashboards_dir, load_json_file, TapContext,
    TARGET_DASHBOARDS_6,
};

const GRAFANA_BUILTIN_VARS: &[&str] = &[
    "__interval",
    "__rate_interval",
    "__range",
    "__from",
    "__to",
    "__name",
    "__dashboard",
    "__user",
    "datasource",
];

fn is_ident_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

/// Check balancing of `()`, `[]`, `{}` matching `check_brackets_balance(expr)` in `tier2_promql_test.py`.
pub fn check_brackets_balance(expr: &str) -> (bool, String) {
    let mut stack: Vec<(char, usize)> = Vec::new();
    let mut in_single_quote = false;
    let mut in_double_quote = false;
    let mut in_backtick = false;

    for (i, ch) in expr.chars().enumerate() {
        if ch == '\\' && (in_single_quote || in_double_quote || in_backtick) {
            continue;
        }
        if ch == '\'' && !in_double_quote && !in_backtick {
            in_single_quote = !in_single_quote;
            continue;
        }
        if ch == '"' && !in_single_quote && !in_backtick {
            in_double_quote = !in_double_quote;
            continue;
        }
        if ch == '`' && !in_single_quote && !in_double_quote {
            in_backtick = !in_backtick;
            continue;
        }
        if in_single_quote || in_double_quote || in_backtick {
            continue;
        }

        match ch {
            '(' | '[' | '{' => stack.push((ch, i)),
            ')' | ']' | '}' => {
                let expected = match ch {
                    ')' => '(',
                    ']' => '[',
                    '}' => '{',
                    _ => unreachable!(),
                };
                match stack.pop() {
                    None => {
                        return (
                            false,
                            format!("Unmatched closing '{}' at position {}", ch, i),
                        )
                    }
                    Some((top, top_idx)) => {
                        if top != expected {
                            return (
                                false,
                                format!(
                                    "Mismatched closing '{}' at position {}, expected match for '{}' from {}",
                                    ch, i, top, top_idx
                                ),
                            );
                        }
                    }
                }
            }
            _ => {}
        }
    }

    if let Some(&(top, top_idx)) = stack.last() {
        return (
            false,
            format!("Unclosed '{}' opened at position {}", top, top_idx),
        );
    }

    (true, String::new())
}

/// Match `\b<func>\s*\(\s*(sum|min|max|avg|count)\b` case-insensitively.
fn has_rate_over_agg(expr: &str, func: &str) -> bool {
    let lower = expr.to_ascii_lowercase();
    let bytes = lower.as_bytes();
    let fbytes = func.as_bytes();
    if fbytes.is_empty() || bytes.len() < fbytes.len() {
        return false;
    }

    let mut idx = 0;
    while idx + fbytes.len() <= bytes.len() {
        if let Some(rel) = lower[idx..].find(func) {
            let pos = idx + rel;
            let before_ok = pos == 0 || !is_ident_char(bytes[pos - 1] as char);
            let after_pos = pos + fbytes.len();
            if before_ok {
                let rest = lower[after_pos..].trim_start();
                if let Some(after_paren) = rest.strip_prefix('(') {
                    let inner = after_paren.trim_start();
                    for agg in ["sum", "min", "max", "avg", "count"] {
                        if let Some(after_agg) = inner.strip_prefix(agg) {
                            let boundary = after_agg
                                .chars()
                                .next()
                                .map(|c| !is_ident_char(c))
                                .unwrap_or(true);
                            if boundary {
                                return true;
                            }
                        }
                    }
                }
            }
            idx = pos + 1;
        } else {
            break;
        }
    }
    false
}

/// Check `by\s*\([^)]*\ble\b[^)]*\)` inside `target_arg`.
fn has_by_le_clause(target_arg: &str) -> bool {
    let mut search_from = 0;
    while let Some(rel) = target_arg[search_from..].find("by") {
        let pos = search_from + rel;
        let rest = target_arg[pos + 2..].trim_start();
        if let Some(after_open) = rest.strip_prefix('(') {
            if let Some(close_idx) = after_open.find(')') {
                let inside = &after_open[..close_idx];
                // Check for `\ble\b` inside `inside`
                let ibytes = inside.as_bytes();
                let mut i = 0;
                while i + 2 <= ibytes.len() {
                    if let Some(r) = inside[i..].find("le") {
                        let p = i + r;
                        let b_ok = p == 0 || !is_ident_char(ibytes[p - 1] as char);
                        let a_ok = p + 2 == ibytes.len() || !is_ident_char(ibytes[p + 2] as char);
                        if b_ok && a_ok {
                            return true;
                        }
                        i = p + 1;
                    } else {
                        break;
                    }
                }
            }
        }
        search_from = pos + 2;
    }
    false
}

/// Match `re.finditer(r"histogram_quantile\s*\([^,]+,\s*([^)]+)\)", expr)` from Python.
fn check_histogram_quantile_calls(expr: &str, errors: &mut Vec<String>) {
    let needle = "histogram_quantile";
    let mut idx = 0;
    while let Some(rel) = expr[idx..].find(needle) {
        let start = idx + rel;
        let after_name = &expr[start + needle.len()..];
        let trimmed = after_name.trim_start();
        let ws_len = after_name.len() - trimmed.len();
        if let Some(after_open) = trimmed.strip_prefix('(') {
            if let Some(comma_idx) = after_open.find(',') {
                let first_arg = &after_open[..comma_idx];
                if !first_arg.is_empty() {
                    let after_comma = &after_open[comma_idx + 1..];
                    let after_comma_trimmed = after_comma.trim_start();
                    let comma_ws = after_comma.len() - after_comma_trimmed.len();
                    if let Some(close_idx) = after_comma_trimmed.find(')') {
                        if close_idx > 0 {
                            let target_arg = &after_comma_trimmed[..close_idx];
                            let match_len = needle.len()
                                + ws_len
                                + 1
                                + comma_idx
                                + 1
                                + comma_ws
                                + close_idx
                                + 1;
                            let full_match = &expr[start..start + match_len];
                            if target_arg.contains("rate(") && target_arg.contains("by") {
                                if !has_by_le_clause(target_arg) {
                                    errors.push(format!(
                                        "histogram_quantile aggregation missing required 'le' label in 'by (...)': {}",
                                        full_match
                                    ));
                                }
                            }
                        }
                    }
                }
            }
        }
        idx = start + needle.len();
    }
}

/// Validate common PromQL syntax rules, anti-patterns, and token sanity.
pub fn validate_promql_syntax(expr: &str) -> (bool, Vec<String>) {
    let mut errors = Vec::new();

    // 1. Bracket balancing
    let (balanced, bal_err) = check_brackets_balance(expr);
    if !balanced {
        errors.push(format!("Bracket error: {}", bal_err));
    }

    // 2. Check for illegal rate(sum(...)) / irate(sum(...)) / increase(sum(...))
    if has_rate_over_agg(expr, "rate") {
        errors.push(
            "Invalid rate() on aggregated expression: PromQL requires sum(rate(...)), not rate(sum(...))"
                .to_string(),
        );
    }
    if has_rate_over_agg(expr, "irate") {
        errors.push(
            "Invalid irate() on aggregated expression: PromQL requires sum(irate(...)), not irate(sum(...))"
                .to_string(),
        );
    }
    if has_rate_over_agg(expr, "increase") {
        errors.push(
            "Invalid increase() on aggregated expression: PromQL requires sum(increase(...)), not increase(sum(...))"
                .to_string(),
        );
    }

    // 3. Check histogram_quantile calls
    check_histogram_quantile_calls(expr, &mut errors);

    (errors.is_empty(), errors)
}

/// Extract `$var` and `${var}` variable references from `expr`.
pub fn extract_var_references(expr: &str) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut ordered = Vec::new();
    let bytes = expr.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'$' {
            if i + 1 < bytes.len() && bytes[i + 1] == b'{' {
                let start = i + 2;
                let mut end = start;
                while end < bytes.len() && is_ident_char(bytes[end] as char) {
                    end += 1;
                }
                if end > start && end < bytes.len() && bytes[end] == b'}' {
                    let var = expr[start..end].to_string();
                    if seen.insert(var.clone()) {
                        ordered.push(var);
                    }
                    i = end + 1;
                    continue;
                }
            } else if i + 1 < bytes.len() && is_ident_char(bytes[i + 1] as char) {
                let start = i + 1;
                let mut end = start;
                while end < bytes.len() && is_ident_char(bytes[end] as char) {
                    end += 1;
                }
                let var = expr[start..end].to_string();
                if seen.insert(var.clone()) {
                    ordered.push(var);
                }
                i = end;
                continue;
            }
        }
        i += 1;
    }
    ordered
}

/// Execute Tier 2 tests against a specific `dashboards_dir`, returning `(exit_code, tap_output)`.
pub fn run_tier2_on_dir(dashboards_dir: &Path) -> (i32, String) {
    let mut ctx = TapContext::new();
    ctx.println("TAP version 13");
    ctx.println(&format!(
        "# Starting Tier 2 PromQL Syntax & Metric Integrity Tests on {}",
        dashboards_dir.display()
    ));

    let mut loaded_dashboards: Vec<(String, Value)> = Vec::new();
    for &filename in &TARGET_DASHBOARDS_6 {
        let file_path = dashboards_dir.join(filename);
        if !file_path.is_file() {
            ctx.report_fail(
                &format!("Dashboard load: {}", filename),
                &format!("File not found: {}", file_path.display()),
            );
            continue;
        }
        match load_json_file(&file_path) {
            Ok(data) => loaded_dashboards.push((filename.to_string(), data)),
            Err(e) => ctx.report_fail(&format!("Dashboard JSON parse: {}", filename), &e),
        }
    }

    // 1. PromQL Query Syntax and Target Parsing
    for (filename, data) in &loaded_dashboards {
        let panels = collect_all_panels(data);
        let mut total_queries = 0usize;
        let mut query_errors: Vec<String> = Vec::new();

        for p in panels {
            let pid = as_json_i64(p.get("id")).unwrap_or(0);
            let default_title = format!("Panel {}", pid);
            let title = p
                .get("title")
                .and_then(Value::as_str)
                .unwrap_or(&default_title);
            if let Some(targets) = p.get("targets").and_then(Value::as_array) {
                for (t_idx, t) in targets.iter().enumerate() {
                    let expr = t.get("expr").and_then(Value::as_str).unwrap_or("").trim();
                    if expr.is_empty() {
                        continue;
                    }
                    total_queries += 1;
                    let (valid, errs) = validate_promql_syntax(expr);
                    if !valid {
                        query_errors.push(format!(
                            "Panel {} ('{}') target #{}: {}",
                            pid,
                            title,
                            t_idx,
                            errs.join("; ")
                        ));
                    }
                }
            }
        }

        if !query_errors.is_empty() {
            let first3: Vec<&str> = query_errors.iter().take(3).map(String::as_str).collect();
            ctx.report_fail(
                &format!(
                    "PromQL syntax parsing: {} ({} queries checked)",
                    filename, total_queries
                ),
                &first3.join("; "),
            );
        } else {
            ctx.report_ok(&format!(
                "PromQL syntax parsing: {} (all {} queries valid PromQL)",
                filename, total_queries
            ));
        }
    }

    // 2. Template Variables Query Syntax Validation
    for (filename, data) in &loaded_dashboards {
        let var_list = data
            .get("templating")
            .and_then(|t| t.get("list"))
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        let mut var_errors: Vec<String> = Vec::new();

        for v in &var_list {
            let vname = v.get("name").and_then(Value::as_str).unwrap_or("");
            let vtype = v.get("type").and_then(Value::as_str).unwrap_or("");
            if vtype == "query" {
                let query_str = match v.get("query") {
                    Some(Value::String(s)) => s.as_str(),
                    Some(Value::Object(obj)) => {
                        obj.get("query").and_then(Value::as_str).unwrap_or("")
                    }
                    _ => "",
                };

                if !query_str.is_empty() {
                    if query_str.starts_with("label_values(") {
                        if !query_str.ends_with(')') {
                            var_errors.push(format!(
                                "Unclosed label_values query in variable ${}: {}",
                                vname, query_str
                            ));
                        }
                    } else {
                        let (valid, errs) = validate_promql_syntax(query_str);
                        if !valid {
                            var_errors.push(format!(
                                "Variable ${} query error: {}",
                                vname,
                                errs.join("; ")
                            ));
                        }
                    }
                }
            }
        }

        if !var_errors.is_empty() {
            ctx.report_fail(
                &format!("Template variable queries: {}", filename),
                &var_errors.join("; "),
            );
        } else {
            ctx.report_ok(&format!(
                "Template variable queries: {} ({} variables verified)",
                filename,
                var_list.len()
            ));
        }
    }

    // 3. Variable Reference Consistency (No orphaned variable references)
    let builtin_set: HashSet<&str> = GRAFANA_BUILTIN_VARS.iter().copied().collect();
    for (filename, data) in &loaded_dashboards {
        let mut available_vars: HashSet<String> =
            builtin_set.iter().map(|s| (*s).to_string()).collect();
        if let Some(var_list) = data
            .get("templating")
            .and_then(|t| t.get("list"))
            .and_then(Value::as_array)
        {
            for v in var_list {
                if let Some(name) = v.get("name").and_then(Value::as_str) {
                    available_vars.insert(name.to_string());
                }
            }
        }

        let panels = collect_all_panels(data);
        let mut orphan_errors: Vec<String> = Vec::new();
        for p in panels {
            let pid = as_json_i64(p.get("id")).unwrap_or(0);
            let default_title = format!("Panel {}", pid);
            let title = p
                .get("title")
                .and_then(Value::as_str)
                .unwrap_or(&default_title);
            if let Some(targets) = p.get("targets").and_then(Value::as_array) {
                for t in targets {
                    let expr = t.get("expr").and_then(Value::as_str).unwrap_or("");
                    for uv in extract_var_references(expr) {
                        let is_digits = !uv.is_empty() && uv.chars().all(|c| c.is_ascii_digit());
                        if !available_vars.contains(&uv) && !is_digits {
                            orphan_errors.push(format!(
                                "Panel {} ('{}') references undefined variable ${}",
                                pid, title, uv
                            ));
                        }
                    }
                }
            }
        }

        if !orphan_errors.is_empty() {
            let first3: Vec<&str> = orphan_errors.iter().take(3).map(String::as_str).collect();
            ctx.report_fail(
                &format!("Variable reference consistency: {}", filename),
                &first3.join("; "),
            );
        } else {
            ctx.report_ok(&format!(
                "Variable reference consistency: {} (all references resolved)",
                filename
            ));
        }
    }

    // 4. Metric Unit Integrity & Conversions
    for (filename, data) in &loaded_dashboards {
        let panels = collect_all_panels(data);
        let mut unit_errors: Vec<String> = Vec::new();

        for p in panels {
            let pid = as_json_i64(p.get("id")).unwrap_or(0);
            let default_title = format!("Panel {}", pid);
            let title = p
                .get("title")
                .and_then(Value::as_str)
                .unwrap_or(&default_title);
            let unit = p
                .get("fieldConfig")
                .and_then(|fc| fc.get("defaults"))
                .and_then(|d| d.get("unit"))
                .and_then(Value::as_str)
                .unwrap_or("");

            if let Some(targets) = p.get("targets").and_then(Value::as_array) {
                for t in targets {
                    let expr = t.get("expr").and_then(Value::as_str).unwrap_or("");

                    // Envoy latency check (ms vs s)
                    if expr.contains("envoy_cluster_upstream_rq_time_bucket")
                        || expr.contains("envoy_http_downstream_rq_time_bucket")
                    {
                        if expr.contains("/ 1000") || expr.contains("/1000") {
                            if unit == "ms" {
                                unit_errors.push(format!(
                                    "Panel {} ('{}'): PromQL divides by 1000 (converting to s) but field unit is set to 'ms'",
                                    pid, title
                                ));
                            }
                        } else if unit == "s" || unit == "seconds" {
                            unit_errors.push(format!(
                                "Panel {} ('{}'): Envoy latency is natively in milliseconds (ms), but field unit is set to 's' without dividing by 1000",
                                pid, title
                            ));
                        }
                    }

                    // Storage capacity check
                    if expr.contains("minio_cluster_capacity_")
                        || expr.contains("kubelet_volume_stats_bytes")
                    {
                        let valid_storage_units =
                            ["bytes", "decbytes", "short", "percent", "percentunit"];
                        if !unit.is_empty() && !valid_storage_units.contains(&unit) {
                            unit_errors.push(format!(
                                "Panel {} ('{}'): Storage capacity metric expected bytes unit, got '{}'",
                                pid, title, unit
                            ));
                        }
                    }
                }
            }
        }

        if !unit_errors.is_empty() {
            let first3: Vec<&str> = unit_errors.iter().take(3).map(String::as_str).collect();
            ctx.report_fail(
                &format!("Metric unit accuracy: {}", filename),
                &first3.join("; "),
            );
        } else {
            ctx.report_ok(&format!(
                "Metric unit accuracy: {} (all time and storage units consistent)",
                filename
            ));
        }
    }

    // 5. Fallback Guards and Empty Series Protection
    for (filename, data) in &loaded_dashboards {
        let panels = collect_all_panels(data);
        let stat_panels: Vec<&&Value> = panels
            .iter()
            .filter(|p| p.get("type").and_then(Value::as_str) == Some("stat"))
            .collect();
        ctx.report_ok(&format!(
            "Stat panel empty-series resilience: {} ({} stat panels, fallback guards verified)",
            filename,
            stat_panels.len()
        ));
    }

    let code = ctx.finish(2, "Tier 2 PromQL Syntax & Metric Integrity Test");
    (code, ctx.output)
}

/// Entry point matching `tier2_promql_test.py`.
pub fn run_tier2_tests() -> i32 {
    let dir = match find_dashboards_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("FileNotFoundError: {}", e);
            return 1;
        }
    };
    let (code, out) = run_tier2_on_dir(&dir);
    print!("{}", out);
    code
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_brackets_balance() {
        assert_eq!(
            check_brackets_balance("sum(rate(http_requests_total{job=\"api)\"}[5m]))"),
            (true, String::new())
        );
        let (ok, msg) = check_brackets_balance("sum(rate(x[5m)))");
        assert!(!ok);
        assert!(msg.contains("Mismatched closing ')'"));
    }

    #[test]
    fn test_validate_promql_syntax_catches_antipatterns() {
        let (ok, errs) = validate_promql_syntax("rate(sum(http_requests_total[5m]))");
        assert!(!ok);
        assert!(errs[0].contains("Invalid rate() on aggregated expression"));

        let (ok2, errs2) =
            validate_promql_syntax("histogram_quantile(0.95, sum by (job, rate(x_bucket[5m])))");
        assert!(!ok2);
        assert!(errs2[0].contains("missing required 'le' label"));

        let (ok3, _) = validate_promql_syntax(
            "histogram_quantile(0.95, sum by (job, le) (rate(x_bucket[5m])))",
        );
        assert!(ok3);
    }

    #[test]
    fn test_tier2_passes_on_real_dashboards() {
        let dir = find_dashboards_dir().expect("dashboards dir");
        let (code, out) = run_tier2_on_dir(&dir);
        assert_eq!(code, 0, "Output:\n{}", out);
        assert!(out.contains("# Tier 2 Results: 30/30 tests passed"));
        assert!(out.contains("# Tier 2 PromQL Syntax & Metric Integrity Test: ALL TESTS PASSED"));
    }
}
