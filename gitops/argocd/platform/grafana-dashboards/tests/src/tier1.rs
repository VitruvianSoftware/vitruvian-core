// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Tier 1: Schema, Structure, & Standard Variable Validation Test.
//!
//! Validates Grafana dashboard JSON schema, UID uniqueness, required tags,
//! datasource and templating variables, panel grid geometry, and field configurations.

use std::collections::{HashMap, HashSet};
use std::path::Path;

use serde_json::Value;

use crate::{
    as_json_i64, collect_all_panels, find_dashboards_dir, load_json_file, py_display_opt, py_repr,
    py_str_repr, TapContext, TARGET_DASHBOARDS_6,
};

const VALID_PANEL_TYPES: &[&str] = &[
    "timeseries",
    "stat",
    "table",
    "bargauge",
    "gauge",
    "row",
    "piechart",
    "logs",
    "alertlist",
    "traces",
    "nodeGraph",
    "state-timeline",
    "status-history",
    "heatmap",
    "geomap",
    "canvas",
    "news",
    "text",
];

fn expected_uids(filename: &str) -> &'static [&'static str] {
    match filename {
        "argocd.json" => &["argocd-gitops", "argocd"],
        "envoy-gateway.json" => &["envoy-gateway-api", "envoy-gateway"],
        "identity-mesh.json" => &["identity-zero-trust", "identity-mesh"],
        "data-platform-dr.json" => &["data-platform-dr", "data-platform"],
        "agent-integrations.json" => &["agent-integrations", "ai-assistants"],
        "ci-pipelines.json" => &["ci-pipelines"],
        _ => &[],
    }
}

fn required_variables(filename: &str) -> &'static [&'static str] {
    match filename {
        "argocd.json" => &["datasource"],
        "envoy-gateway.json" => &["datasource"],
        "identity-mesh.json" => &["datasource"],
        "data-platform-dr.json" => &["datasource"],
        "agent-integrations.json" => &["datasource"],
        "ci-pipelines.json" => &["datasource", "workflow", "trigger"],
        _ => &[],
    }
}

/// Execute Tier 1 tests against a specific `dashboards_dir`, returning `(exit_code, tap_output)`.
pub fn run_tier1_on_dir(dashboards_dir: &Path) -> (i32, String) {
    let mut ctx = TapContext::new();
    ctx.println("TAP version 13");
    ctx.println(&format!(
        "# Starting Tier 1 Dashboard Schema & Structure Tests on {}",
        dashboards_dir.display()
    ));

    let mut loaded_dashboards: Vec<(String, Value)> = Vec::new();

    // 1. Test existence and JSON validity of all target dashboards
    for &filename in &TARGET_DASHBOARDS_6 {
        let file_path = dashboards_dir.join(filename);
        if !file_path.is_file() {
            ctx.report_fail(
                &format!("File existence: {}", filename),
                &format!("Dashboard file does not exist at {}", file_path.display()),
            );
            continue;
        }
        match load_json_file(&file_path) {
            Ok(data) => {
                loaded_dashboards.push((filename.to_string(), data));
                ctx.report_ok(&format!("File existence and JSON parsing: {}", filename));
            }
            Err(e) => {
                ctx.report_fail(
                    &format!("JSON syntax validity: {}", filename),
                    &format!("Invalid JSON syntax: {}", e),
                );
            }
        }
    }

    // 2. Schema version validation
    for (filename, data) in &loaded_dashboards {
        let schema_ver = data.get("schemaVersion");
        if let Some(ver) = as_json_i64(schema_ver) {
            if ver >= 38 {
                ctx.report_ok(&format!(
                    "Schema version compatibility (>=38): {} (v{})",
                    filename, ver
                ));
            } else {
                ctx.report_fail(
                    &format!("Schema version compatibility (>=38): {}", filename),
                    &format!("Expected schemaVersion >= 38, found: {}", ver),
                );
            }
        } else {
            ctx.report_fail(
                &format!("Schema version compatibility (>=38): {}", filename),
                &format!(
                    "Expected schemaVersion >= 38, found: {}",
                    py_display_opt(schema_ver)
                ),
            );
        }
    }

    // 3. UID validation and global uniqueness
    let mut seen_uids: HashMap<String, String> = HashMap::new();
    for (filename, data) in &loaded_dashboards {
        let uid_opt = data.get("uid").and_then(Value::as_str);
        match uid_opt {
            None => {
                ctx.report_fail(
                    &format!("UID validation: {}", filename),
                    &format!("Missing or empty UID in {}", filename),
                );
            }
            Some(uid) if uid.trim().is_empty() => {
                ctx.report_fail(
                    &format!("UID validation: {}", filename),
                    &format!("Missing or empty UID in {}", filename),
                );
            }
            Some(uid) if uid.contains(' ') => {
                ctx.report_fail(
                    &format!("UID validation: {}", filename),
                    &format!("UID contains invalid whitespace: '{}'", uid),
                );
            }
            Some(uid) => {
                let expected_list = expected_uids(filename);
                if !expected_list.is_empty() && !expected_list.contains(&uid) {
                    ctx.report_ok(&format!(
                        "UID validation: {} (uid='{}', convention='{}')",
                        filename, uid, expected_list[0]
                    ));
                } else {
                    ctx.report_ok(&format!("UID validation: {} (uid='{}')", filename, uid));
                }

                if let Some(prev_file) = seen_uids.get(uid) {
                    ctx.report_fail(
                        &format!("UID uniqueness: {}", filename),
                        &format!(
                            "Duplicate UID '{}' found in both {} and {}",
                            uid, prev_file, filename
                        ),
                    );
                } else {
                    seen_uids.insert(uid.to_string(), filename.clone());
                    ctx.report_ok(&format!("UID uniqueness check: {} ('{}')", filename, uid));
                }
            }
        }
    }

    // 4. Title, description, editable, and tag conventions
    for (filename, data) in &loaded_dashboards {
        let title_opt = data.get("title").and_then(Value::as_str);
        if let Some(title) = title_opt {
            if !title.trim().is_empty() {
                ctx.report_ok(&format!("Title presence: {} ('{}')", filename, title));
            } else {
                ctx.report_fail(
                    &format!("Title presence: {}", filename),
                    "Missing or empty dashboard title",
                );
            }
        } else {
            ctx.report_fail(
                &format!("Title presence: {}", filename),
                "Missing or empty dashboard title",
            );
        }

        let editable = data.get("editable");
        if editable == Some(&Value::Bool(true)) {
            ctx.report_ok(&format!("Editable flag set: {}", filename));
        } else {
            ctx.report_fail(
                &format!("Editable flag set: {}", filename),
                &format!("Expected editable=true, got {}", py_display_opt(editable)),
            );
        }

        let tags = data.get("tags");
        if let Some(Value::Array(arr)) = tags {
            if arr.len() >= 2 {
                ctx.report_ok(&format!(
                    "Tags validation: {} ({})",
                    filename,
                    py_repr(tags.unwrap())
                ));
            } else {
                ctx.report_fail(
                    &format!("Tags validation: {}", filename),
                    &format!(
                        "Expected tags list with >=2 tags, got {}",
                        py_repr(tags.unwrap())
                    ),
                );
            }
        } else {
            ctx.report_fail(
                &format!("Tags validation: {}", filename),
                &format!(
                    "Expected tags list with >=2 tags, got {}",
                    py_display_opt(tags)
                ),
            );
        }
    }

    // 5. Time range and refresh configuration
    for (filename, data) in &loaded_dashboards {
        let time_cfg = data.get("time");
        if let Some(Value::Object(map)) = time_cfg {
            if let (Some(from_v), Some(to_v)) = (map.get("from"), map.get("to")) {
                ctx.report_ok(&format!(
                    "Time range definition: {} ({} to {})",
                    filename,
                    py_display_opt(Some(from_v)),
                    py_display_opt(Some(to_v))
                ));
            } else {
                ctx.report_fail(
                    &format!("Time range definition: {}", filename),
                    &format!(
                        "Missing time.from or time.to in {}",
                        py_repr(time_cfg.unwrap())
                    ),
                );
            }
        } else {
            ctx.report_fail(
                &format!("Time range definition: {}", filename),
                &format!(
                    "Missing time.from or time.to in {}",
                    time_cfg.map(py_repr).unwrap_or_else(|| "{}".to_string())
                ),
            );
        }

        let refresh = data.get("refresh");
        if let Some(Value::String(r)) = refresh {
            if !r.is_empty() {
                ctx.report_ok(&format!(
                    "Auto-refresh interval: {} (refresh='{}')",
                    filename, r
                ));
            } else {
                ctx.report_fail(
                    &format!("Auto-refresh interval: {}", filename),
                    &format!("Missing or invalid refresh interval: {}", r),
                );
            }
        } else {
            ctx.report_fail(
                &format!("Auto-refresh interval: {}", filename),
                &format!(
                    "Missing or invalid refresh interval: {}",
                    py_display_opt(refresh)
                ),
            );
        }
    }

    // 6. Templating variables ($datasource and domain drill-down variables)
    for (filename, data) in &loaded_dashboards {
        let templating = data.get("templating");
        let var_list_val = match templating {
            Some(Value::Object(map)) => map.get("list"),
            _ => None,
        };
        let var_list = match var_list_val {
            None => Vec::new(),
            Some(Value::Array(arr)) => arr.clone(),
            Some(_) => {
                ctx.report_fail(
                    &format!("Templating list: {}", filename),
                    "templating.list is not a list",
                );
                continue;
            }
        };

        let mut var_keys_ordered: Vec<String> = Vec::new();
        let mut var_names: HashMap<String, &Value> = HashMap::new();
        for v in &var_list {
            if let Value::Object(obj) = v {
                if let Some(Value::String(name)) = obj.get("name") {
                    if !var_names.contains_key(name) {
                        var_keys_ordered.push(name.clone());
                    }
                    var_names.insert(name.clone(), v);
                }
            }
        }

        let ds_var = var_names.get("datasource").copied();
        let ds_ok = ds_var
            .and_then(|v| {
                let t = v.get("type").and_then(Value::as_str)?;
                let q = v.get("query").and_then(Value::as_str)?;
                Some(t == "datasource" && q == "prometheus")
            })
            .unwrap_or(false);

        if ds_ok {
            ctx.report_ok(&format!(
                "Datasource variable configuration: {} ($datasource)",
                filename
            ));
        } else {
            ctx.report_fail(
                &format!("Datasource variable configuration: {}", filename),
                &format!(
                    "Missing or invalid $datasource variable: {}",
                    ds_var.map(py_repr).unwrap_or_else(|| "None".to_string())
                ),
            );
        }

        for &ev in required_variables(filename) {
            if var_names.contains_key(ev) {
                ctx.report_ok(&format!("Required template variable ${}: {}", ev, filename));
            } else {
                let keys_fmt: Vec<String> =
                    var_keys_ordered.iter().map(|k| py_str_repr(k)).collect();
                ctx.report_fail(
                    &format!("Required template variable ${}: {}", ev, filename),
                    &format!(
                        "Variable ${} not found in templating list: [{}]",
                        ev,
                        keys_fmt.join(", ")
                    ),
                );
            }
        }
    }

    // 7. Panels structure, geometry, and target validation
    let valid_types: HashSet<&str> = VALID_PANEL_TYPES.iter().copied().collect();
    for (filename, data) in &loaded_dashboards {
        let panels = collect_all_panels(data);
        if panels.len() < 4 {
            ctx.report_fail(
                &format!("Panel quantity check: {}", filename),
                &format!(
                    "Expected >= 4 panels for production dashboard, found {}",
                    panels.len()
                ),
            );
            continue;
        }
        ctx.report_ok(&format!(
            "Panel quantity check: {} ({} panels)",
            filename,
            panels.len()
        ));

        let mut seen_panel_ids: HashSet<i64> = HashSet::new();
        let mut panel_errors: Vec<String> = Vec::new();

        for (idx, p) in panels.iter().enumerate() {
            let pid_val = p.get("id");
            let pid_opt = as_json_i64(pid_val);
            let ptype = p.get("type").and_then(Value::as_str);
            let title = p.get("title").and_then(Value::as_str).unwrap_or("");
            let grid_pos = p.get("gridPos");

            // ID validation
            match pid_opt {
                Some(pid) if pid > 0 => {
                    if seen_panel_ids.contains(&pid) {
                        panel_errors
                            .push(format!("Duplicate panel ID {} in panel '{}'", pid, title));
                    } else {
                        seen_panel_ids.insert(pid);
                    }
                }
                _ => {
                    panel_errors.push(format!(
                        "Panel index {} has invalid ID: {}",
                        idx,
                        py_display_opt(pid_val)
                    ));
                }
            }

            let pid_display = py_display_opt(pid_val);

            // Panel type validation
            let ptype_str = ptype.unwrap_or("None");
            if !valid_types.contains(ptype_str) {
                panel_errors.push(format!(
                    "Panel {} ('{}') has unknown type '{}'",
                    pid_display, title, ptype_str
                ));
            }

            // Grid position geometry
            match grid_pos {
                Some(Value::Object(gp)) => {
                    let h = as_json_i64(gp.get("h")).unwrap_or(0);
                    let w = as_json_i64(gp.get("w")).unwrap_or(0);
                    let x = as_json_i64(gp.get("x")).unwrap_or(-1);
                    let y = as_json_i64(gp.get("y")).unwrap_or(-1);
                    if h <= 0 || w <= 0 || w > 24 || x < 0 || x >= 24 || y < 0 {
                        panel_errors.push(format!(
                            "Panel {} ('{}') has out-of-bounds gridPos: h={}, w={}, x={}, y={}",
                            pid_display, title, h, w, x, y
                        ));
                    }
                    if x + w > 24 {
                        panel_errors.push(format!(
                            "Panel {} ('{}') grid width overflows 24-col grid: x({}) + w({}) = {}",
                            pid_display,
                            title,
                            x,
                            w,
                            x + w
                        ));
                    }
                }
                None => {
                    // Python: `grid_pos = p.get("gridPos", {})` -> dict with defaults h=0, w=0, x=-1, y=-1
                    panel_errors.push(format!(
                        "Panel {} ('{}') has out-of-bounds gridPos: h=0, w=0, x=-1, y=-1",
                        pid_display, title
                    ));
                }
                Some(_) => {
                    panel_errors.push(format!("Panel {} missing gridPos dictionary", pid_display));
                }
            }

            // Target validation for non-row/text/news panels
            if ptype_str != "row" && ptype_str != "text" && ptype_str != "news" {
                let targets = p.get("targets");
                match targets {
                    Some(Value::Array(t_arr)) if !t_arr.is_empty() => {
                        for (t_idx, target) in t_arr.iter().enumerate() {
                            if let Value::Object(t_obj) = target {
                                let has_expr = t_obj
                                    .get("expr")
                                    .and_then(Value::as_str)
                                    .map(|s| !s.is_empty())
                                    .unwrap_or(false);
                                let has_query = t_obj
                                    .get("query")
                                    .and_then(Value::as_str)
                                    .map(|s| !s.is_empty())
                                    .unwrap_or(false);
                                if !has_expr && !has_query {
                                    panel_errors.push(format!(
                                        "Panel {} target #{} missing 'expr' query",
                                        pid_display, t_idx
                                    ));
                                }
                            } else {
                                panel_errors.push(format!(
                                    "Panel {} target #{} is not a dict",
                                    pid_display, t_idx
                                ));
                            }
                        }
                    }
                    _ => {
                        panel_errors.push(format!(
                            "Panel {} ('{}', type '{}') has no query targets",
                            pid_display, title, ptype_str
                        ));
                    }
                }
            }
        }

        if !panel_errors.is_empty() {
            let preview: Vec<&str> = panel_errors.iter().take(5).map(String::as_str).collect();
            let suffix = if panel_errors.len() > 5 {
                format!(" (+{} more)", panel_errors.len() - 5)
            } else {
                String::new()
            };
            ctx.report_fail(
                &format!("Panel structure & geometry: {}", filename),
                &format!("{}{}", preview.join("; "), suffix),
            );
        } else {
            ctx.report_ok(&format!(
                "Panel structure, IDs, geometry, and targets: {} (all {} panels valid)",
                filename,
                panels.len()
            ));
        }
    }

    let code = ctx.finish(1, "Tier 1 Schema & Structure Test");
    (code, ctx.output)
}

/// Entry point matching `tier1_schema_test.py`.
pub fn run_tier1_tests() -> i32 {
    let dir = match find_dashboards_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("FileNotFoundError: {}", e);
            return 1;
        }
    };
    let (code, out) = run_tier1_on_dir(&dir);
    print!("{}", out);
    code
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn test_tier1_passes_on_real_dashboards() {
        let dir = find_dashboards_dir().expect("dashboards dir");
        let (code, out) = run_tier1_on_dir(&dir);
        assert_eq!(code, 0, "Output:\n{}", out);
        assert!(out.contains("# Tier 1 Results: 80/80 tests passed"));
        assert!(out.contains("# Tier 1 Schema & Structure Test: ALL TESTS PASSED"));
    }

    #[test]
    fn test_tier1_catches_invalid_schema_and_duplicate_uids() {
        let tmp = std::env::temp_dir().join(format!("tier1-unit-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();

        let bad_dash = r#"{
            "schemaVersion": 30,
            "uid": "dup-uid",
            "title": "",
            "editable": false,
            "tags": ["only-one"],
            "time": {},
            "refresh": "",
            "templating": {"list": []},
            "panels": [
                {"id": 1, "type": "unknown_type", "title": "P1", "gridPos": {"h": 4, "w": 20, "x": 10, "y": 0}},
                {"id": 1, "type": "stat", "title": "P2", "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0}, "targets": []},
                {"id": 3, "type": "stat", "title": "P3", "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0}, "targets": [{"expr": "up"}]},
                {"id": 4, "type": "stat", "title": "P4", "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0}, "targets": [{"expr": "up"}]}
            ]
        }"#;
        fs::write(tmp.join("argocd.json"), bad_dash).unwrap();
        fs::write(tmp.join("envoy-gateway.json"), bad_dash).unwrap();
        fs::write(tmp.join("identity-mesh.json"), "{ invalid json").unwrap();

        let (code, out) = run_tier1_on_dir(&tmp);
        let _ = fs::remove_dir_all(&tmp);
        assert_eq!(code, 1);
        assert!(out.contains("not ok"));
        assert!(out.contains("Duplicate UID 'dup-uid'"));
        assert!(out.contains("Expected schemaVersion >= 38, found: 30"));
        assert!(out.contains("grid width overflows 24-col grid"));
    }
}
