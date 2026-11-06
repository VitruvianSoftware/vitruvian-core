// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

pub mod openui;

use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, HashSet};
use std::fs;
use std::path::Path;

pub fn marketplace_catalog() -> Vec<Value> {
    vec![
        json!({
            "name": "gh-watch",
            "version": "1.6.0",
            "description": "Watches GitHub pull requests for CI failures, merge queue progress, review requests, and merge conflicts.",
            "repository": "https://github.com/VitruvianSoftware/gh-watch",
            "category": "ci-cd",
            "hasSidecar": true,
            "skills": ["gh-watch"],
            "hooks": ["PostToolUse"],
            "rules": ["AGENTS.md"]
        }),
        json!({
            "name": "worktree-band",
            "version": "0.1.0",
            "description": "Monitors git worktrees, open PRs, CI status, and local caches across active repositories.",
            "repository": "https://github.com/VitruvianSoftware/worktree-band",
            "category": "git-hygiene",
            "hasSidecar": true,
            "skills": ["worktree-band"],
            "hooks": [],
            "rules": []
        }),
        json!({
            "name": "ralph-loop",
            "version": "0.1.0",
            "description": "Autonomous iterative agent loop engine with completion-promise verification and bounded iteration control.",
            "repository": "https://github.com/VitruvianSoftware/ralph-loop",
            "category": "autonomy",
            "hasSidecar": true,
            "skills": ["ralph-loop"],
            "hooks": ["Stop"],
            "rules": ["AGENTS.md"]
        }),
        json!({
            "name": "hookify",
            "version": "0.1.0",
            "description": "User-configurable markdown guardrails (.gemini/hookify.*.local.md) with live rule builder and test runner.",
            "repository": "https://github.com/VitruvianSoftware/hookify",
            "category": "guardrails",
            "hasSidecar": true,
            "skills": ["hookify"],
            "hooks": ["PreToolUse", "Stop"],
            "rules": ["AGENTS.md"]
        }),
        json!({
            "name": "security-guidance",
            "version": "0.1.0",
            "description": "Pre-commit and PreToolUse vulnerability scanner detecting command injection, XSS, eval, and unsafe patterns.",
            "repository": "https://github.com/VitruvianSoftware/security-guidance",
            "category": "security",
            "hasSidecar": true,
            "skills": ["security-guidance"],
            "hooks": ["PreToolUse"],
            "rules": ["AGENTS.md"]
        }),
        json!({
            "name": "receipts-report",
            "version": "0.1.0",
            "description": "Local-first session analytics, token velocity, tool call breakdown, and CSV/HTML receipt exporter.",
            "repository": "https://github.com/VitruvianSoftware/receipts-report",
            "category": "analytics",
            "hasSidecar": true,
            "skills": ["receipts-report"],
            "hooks": [],
            "rules": ["AGENTS.md"]
        }),
        json!({
            "name": "savvy-fleet",
            "version": "0.1.0",
            "description": "Subagent fleet telemetry and savvy-flow tiered orchestration board (Plan -> Design -> Delegate -> Review -> Close).",
            "repository": "https://github.com/VitruvianSoftware/savvy-fleet",
            "category": "orchestration",
            "hasSidecar": true,
            "skills": ["savvy-fleet", "savvy-flow"],
            "hooks": ["PostToolUse"],
            "rules": ["AGENTS.md"]
        }),
        json!({
            "name": "live-context",
            "version": "0.1.0",
            "description": "PreInvocation live Git/GitHub context injector and adaptive Stop response-contract verifier.",
            "repository": "https://github.com/VitruvianSoftware/live-context",
            "category": "context",
            "hasSidecar": true,
            "skills": ["live-context"],
            "hooks": ["PreInvocation", "Stop"],
            "rules": ["AGENTS.md"]
        }),
        json!({
            "name": "ext-marketplace",
            "version": "0.1.0",
            "description": "Extensions Marketplace and installed plugin manager sidecar for Antigravity.",
            "repository": "https://github.com/VitruvianSoftware/ext-marketplace",
            "category": "marketplace",
            "hasSidecar": true,
            "skills": ["ext-marketplace"],
            "hooks": ["PostToolUse"],
            "rules": ["AGENTS.md"]
        }),
    ]
}

pub fn inspect_plugin_dir_meta(plugin_dir: &Path) -> Value {
    let manifest_path = plugin_dir.join("plugin.json");
    if !manifest_path.exists() {
        return Value::Null;
    }

    let Ok(raw_str) = fs::read_to_string(&manifest_path) else {
        return Value::Null;
    };
    let Ok(raw) = serde_json::from_str::<Value>(&raw_str) else {
        return Value::Null;
    };

    let mut skills = Vec::new();
    let skills_dir = plugin_dir.join("skills");
    if skills_dir.exists() {
        if let Ok(entries) = fs::read_dir(&skills_dir) {
            for entry in entries.flatten() {
                if entry.file_type().map(|t| t.is_dir()).unwrap_or(false)
                    && entry.path().join("SKILL.md").exists()
                {
                    if let Some(name) = entry.file_name().to_str() {
                        skills.push(Value::String(name.to_string()));
                    }
                }
            }
        }
    }

    let mut hooks = Vec::new();
    let hooks_file = plugin_dir.join("hooks").join("hooks.json");
    if hooks_file.exists() {
        if let Ok(h_str) = fs::read_to_string(&hooks_file) {
            if let Ok(h_json) = serde_json::from_str::<Value>(&h_str) {
                if let Some(h_obj) = h_json.get("hooks").and_then(|v| v.as_object()) {
                    for k in h_obj.keys() {
                        hooks.push(Value::String(k.clone()));
                    }
                }
            }
        }
    }

    let mut rules = Vec::new();
    let rules_dir = plugin_dir.join("rules");
    if rules_dir.exists() {
        if let Ok(entries) = fs::read_dir(&rules_dir) {
            for entry in entries.flatten() {
                if let Some(name) = entry.file_name().to_str() {
                    if name.ends_with(".md") {
                        rules.push(Value::String(name.to_string()));
                    }
                }
            }
        }
    }

    let has_sidecar = plugin_dir
        .join("sidecars")
        .join("panel")
        .join("package.json")
        .exists();
    let fallback_name = plugin_dir
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("");

    json!({
        "name": raw.get("name").and_then(|v| v.as_str()).unwrap_or(fallback_name),
        "version": raw.get("version").and_then(|v| v.as_str()).unwrap_or("0.0.0"),
        "description": raw.get("description").and_then(|v| v.as_str()).unwrap_or(""),
        "repository": raw.get("repository").and_then(|v| v.as_str()).unwrap_or(""),
        "skills": skills,
        "hooks": hooks,
        "rules": rules,
        "hasSidecar": has_sidecar,
        "path": plugin_dir.to_string_lossy(),
    })
}

pub fn apply_plugin_toggle_to_config(
    config_raw: Option<&Value>,
    plugin_name: &str,
    enabled: bool,
) -> Result<Value, String> {
    if plugin_name.is_empty() {
        return Err("pluginName must be a non-empty string".to_string());
    }

    let mut base = match config_raw {
        Some(Value::Object(m)) => m.clone(),
        _ => Map::new(),
    };
    let mut plugins_map = match base.get("plugins") {
        Some(Value::Object(m)) => m.clone(),
        _ => Map::new(),
    };
    let mut existing = match plugins_map.get(plugin_name) {
        Some(Value::Object(m)) => m.clone(),
        _ => Map::new(),
    };

    existing.insert("enabled".to_string(), Value::Bool(enabled));
    plugins_map.insert(plugin_name.to_string(), Value::Object(existing));
    base.insert("plugins".to_string(), Value::Object(plugins_map));

    Ok(Value::Object(base))
}

pub fn merge_installed_with_catalog(
    catalog: &[Value],
    installed_dirs: &[Value],
    config_plugins: Option<&Value>,
) -> Vec<Value> {
    let mut by_name: BTreeMap<String, Map<String, Value>> = BTreeMap::new();
    let mut order: Vec<String> = Vec::new();
    let cfg_map = config_plugins.and_then(|v| v.as_object());

    for item in catalog {
        let Some(obj) = item.as_object() else {
            continue;
        };
        let Some(name) = obj.get("name").and_then(|v| v.as_str()) else {
            continue;
        };
        let mut entry = obj.clone();
        let cfg_entry = cfg_map
            .and_then(|m| m.get(name))
            .and_then(|v| v.as_object());
        let enabled = cfg_entry
            .and_then(|e| e.get("enabled"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let installed_from = cfg_entry
            .and_then(|e| e.get("installedFrom"))
            .cloned()
            .unwrap_or(Value::Null);
        entry.insert("inCatalog".to_string(), Value::Bool(true));
        entry.insert("installed".to_string(), Value::Bool(false));
        entry.insert("enabled".to_string(), Value::Bool(enabled));
        entry.insert("installedFrom".to_string(), installed_from);
        if !by_name.contains_key(name) {
            order.push(name.to_string());
        }
        by_name.insert(name.to_string(), entry);
    }

    for inst in installed_dirs {
        let Some(inst_obj) = inst.as_object() else {
            continue;
        };
        let Some(name) = inst_obj.get("name").and_then(|v| v.as_str()) else {
            continue;
        };
        let cfg_entry = cfg_map
            .and_then(|m| m.get(name))
            .and_then(|v| v.as_object());
        let enabled = cfg_entry
            .and_then(|e| e.get("enabled"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let installed_from = cfg_entry
            .and_then(|e| e.get("installedFrom"))
            .cloned()
            .unwrap_or(Value::Null);

        if let Some(existing) = by_name.get_mut(name) {
            let cat_version = existing
                .get("version")
                .cloned()
                .unwrap_or_else(|| json!("0.0.0"));
            let inst_version = inst_obj
                .get("version")
                .cloned()
                .unwrap_or_else(|| cat_version.clone());
            existing.insert("version".to_string(), inst_version);
            existing.insert("catalogVersion".to_string(), cat_version);
            if let Some(desc) = inst_obj.get("description").and_then(|v| v.as_str()) {
                if !desc.is_empty() {
                    existing.insert("description".to_string(), Value::String(desc.to_string()));
                }
            }
            if let Some(skills) = inst_obj.get("skills").and_then(|v| v.as_array()) {
                if !skills.is_empty() {
                    existing.insert("skills".to_string(), Value::Array(skills.clone()));
                }
            }
            if let Some(hooks) = inst_obj.get("hooks").and_then(|v| v.as_array()) {
                if !hooks.is_empty() {
                    existing.insert("hooks".to_string(), Value::Array(hooks.clone()));
                }
            }
            if let Some(rules) = inst_obj.get("rules").and_then(|v| v.as_array()) {
                if !rules.is_empty() {
                    existing.insert("rules".to_string(), Value::Array(rules.clone()));
                }
            }
            let has_sidecar = inst_obj
                .get("hasSidecar")
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
                || existing
                    .get("hasSidecar")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
            existing.insert("hasSidecar".to_string(), Value::Bool(has_sidecar));
            existing.insert("installed".to_string(), Value::Bool(true));
            existing.insert("enabled".to_string(), Value::Bool(enabled));
            existing.insert("installedFrom".to_string(), installed_from);
            existing.insert(
                "localPath".to_string(),
                inst_obj.get("path").cloned().unwrap_or(Value::Null),
            );
        } else {
            let mut entry = inst_obj.clone();
            entry.insert("inCatalog".to_string(), Value::Bool(false));
            entry.insert("installed".to_string(), Value::Bool(true));
            entry.insert("enabled".to_string(), Value::Bool(enabled));
            entry.insert("installedFrom".to_string(), installed_from);
            entry.insert(
                "localPath".to_string(),
                inst_obj.get("path").cloned().unwrap_or(Value::Null),
            );
            order.push(name.to_string());
            by_name.insert(name.to_string(), entry);
        }
    }

    order
        .into_iter()
        .filter_map(|name| by_name.remove(&name).map(Value::Object))
        .collect()
}

pub fn summarise_marketplace(params: &Value) -> Value {
    let default_cat = marketplace_catalog();
    let catalog = params
        .get("catalog")
        .and_then(|v| v.as_array())
        .map(|v| v.as_slice())
        .unwrap_or(&default_cat);
    let installed_dirs = params
        .get("installedDirs")
        .and_then(|v| v.as_array())
        .map(|v| v.as_slice())
        .unwrap_or(&[]);
    let config_plugins = params.get("configPlugins");

    let merged = merge_installed_with_catalog(catalog, installed_dirs, config_plugins);
    let total_catalog = merged
        .iter()
        .filter(|p| {
            p.get("inCatalog")
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
        })
        .count();
    let installed_count = merged
        .iter()
        .filter(|p| {
            p.get("installed")
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
        })
        .count();
    let enabled_count = merged
        .iter()
        .filter(|p| p.get("enabled").and_then(|v| v.as_bool()).unwrap_or(false))
        .count();
    let total_skills: usize = merged
        .iter()
        .map(|p| {
            p.get("skills")
                .and_then(|v| v.as_array())
                .map(|a| a.len())
                .unwrap_or(0)
        })
        .sum();
    let total_hooks: usize = merged
        .iter()
        .map(|p| {
            p.get("hooks")
                .and_then(|v| v.as_array())
                .map(|a| a.len())
                .unwrap_or(0)
        })
        .sum();

    let mut categories = Vec::new();
    let mut seen_cats = HashSet::new();
    for p in &merged {
        let cat = p
            .get("category")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or("custom");
        if seen_cats.insert(cat.to_string()) {
            categories.push(Value::String(cat.to_string()));
        }
    }

    json!({
        "plugins": merged,
        "summary": {
            "totalCatalog": total_catalog,
            "installedCount": installed_count,
            "enabledCount": enabled_count,
            "totalSkills": total_skills,
            "totalHooks": total_hooks,
            "categories": categories,
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn marketplace_catalog_contains_all_9_first_party_vitruvian_plugins() {
        let cat = marketplace_catalog();
        assert_eq!(cat.len(), 9);
        let mut names: Vec<&str> = cat
            .iter()
            .filter_map(|p| p.get("name").and_then(|v| v.as_str()))
            .collect();
        names.sort_unstable();
        assert_eq!(
            names,
            vec![
                "ext-marketplace",
                "gh-watch",
                "hookify",
                "live-context",
                "ralph-loop",
                "receipts-report",
                "savvy-fleet",
                "security-guidance",
                "worktree-band",
            ]
        );
    }

    #[test]
    fn apply_plugin_toggle_to_config_toggles_enabled_without_clobbering_other_fields() {
        let initial = json!({
            "plugins": {
                "gh-watch": {
                    "enabled": true,
                    "installedFrom": { "type": "local", "path": "/some/path" }
                }
            },
            "otherKey": 123
        });

        let disabled = apply_plugin_toggle_to_config(Some(&initial), "gh-watch", false).unwrap();
        assert_eq!(disabled["plugins"]["gh-watch"]["enabled"], json!(false));
        assert_eq!(
            disabled["plugins"]["gh-watch"]["installedFrom"]["path"],
            json!("/some/path")
        );
        assert_eq!(disabled["otherKey"], json!(123));

        let added = apply_plugin_toggle_to_config(Some(&disabled), "ralph-loop", true).unwrap();
        assert_eq!(added["plugins"]["ralph-loop"]["enabled"], json!(true));
    }

    #[test]
    fn inspect_plugin_dir_meta_reads_plugin_json_skills_hooks_and_rules() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let tmp = std::env::temp_dir().join(format!("ext-mp-test-{nanos}"));
        let p_dir = tmp.join("demo-plugin");
        fs::create_dir_all(p_dir.join("skills").join("my-skill")).unwrap();
        fs::create_dir_all(p_dir.join("hooks")).unwrap();
        fs::create_dir_all(p_dir.join("rules")).unwrap();
        fs::create_dir_all(p_dir.join("sidecars").join("panel")).unwrap();

        fs::write(
            p_dir.join("plugin.json"),
            serde_json::to_string(&json!({
                "name": "demo-plugin",
                "version": "1.2.3",
                "description": "Demo"
            }))
            .unwrap(),
        )
        .unwrap();
        fs::write(
            p_dir.join("skills").join("my-skill").join("SKILL.md"),
            "# Skill",
        )
        .unwrap();
        fs::write(
            p_dir.join("hooks").join("hooks.json"),
            serde_json::to_string(&json!({ "hooks": { "Stop": [] } })).unwrap(),
        )
        .unwrap();
        fs::write(p_dir.join("rules").join("AGENTS.md"), "# Rule").unwrap();
        fs::write(
            p_dir.join("sidecars").join("panel").join("package.json"),
            "{}",
        )
        .unwrap();

        let meta = inspect_plugin_dir_meta(&p_dir);
        assert_eq!(meta["name"], json!("demo-plugin"));
        assert_eq!(meta["version"], json!("1.2.3"));
        assert_eq!(meta["skills"], json!(["my-skill"]));
        assert_eq!(meta["hooks"], json!(["Stop"]));
        assert_eq!(meta["rules"], json!(["AGENTS.md"]));
        assert_eq!(meta["hasSidecar"], json!(true));

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn summarise_marketplace_merges_catalog_and_installed_plugins() {
        let state = summarise_marketplace(&json!({
            "installedDirs": [
                {
                    "name": "gh-watch",
                    "version": "1.6.0",
                    "skills": ["gh-watch"],
                    "hooks": ["PostToolUse"],
                    "hasSidecar": true,
                    "path": "/p/gh-watch"
                }
            ],
            "configPlugins": {
                "gh-watch": { "enabled": true }
            }
        }));

        assert_eq!(state["summary"]["totalCatalog"], json!(9));
        assert_eq!(state["summary"]["installedCount"], json!(1));
        assert_eq!(state["summary"]["enabledCount"], json!(1));
        let ghw = state["plugins"]
            .as_array()
            .unwrap()
            .iter()
            .find(|p| p["name"] == "gh-watch")
            .unwrap();
        assert_eq!(ghw["installed"], json!(true));
        assert_eq!(ghw["enabled"], json!(true));
    }
}
