// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

pub mod openui;

use serde_json::{json, Value};

const PASSED: [&str; 3] = ["SUCCESS", "SKIPPED", "NEUTRAL"];
const RUNNING: [&str; 6] = [
    "PENDING",
    "EXPECTED",
    "QUEUED",
    "IN_PROGRESS",
    "WAITING",
    "REQUESTED",
];

pub fn fmt_size(kb: Option<f64>) -> String {
    let Some(n) = kb.filter(|v| v.is_finite()) else {
        return "…".to_string();
    };
    if n >= 1024.0 * 1024.0 {
        format!("{:.1} GB", n / 1024.0 / 1024.0)
    } else if n >= 1024.0 {
        format!("{} MB", (n / 1024.0).round() as i64)
    } else {
        format!("{} KB", (n.round() as i64).max(0))
    }
}

pub fn count_checks(rollup: Option<&[Value]>) -> Value {
    let list = rollup.unwrap_or(&[]);
    let mut passed = 0i64;
    let mut failed = 0i64;
    let mut running = 0i64;
    for r in list {
        let Some(obj) = r.as_object() else {
            continue;
        };
        let verdict = if let Some(st) = obj.get("state").and_then(|v| v.as_str()) {
            st
        } else {
            let status = obj.get("status").and_then(|v| v.as_str()).unwrap_or("");
            if status == "COMPLETED" {
                obj.get("conclusion").and_then(|v| v.as_str()).unwrap_or("")
            } else {
                status
            }
        };
        if PASSED.contains(&verdict) {
            passed += 1;
        } else if RUNNING.contains(&verdict) || verdict.is_empty() {
            running += 1;
        } else {
            failed += 1;
        }
    }
    json!({
        "passed": passed,
        "failed": failed,
        "running": running,
        "total": list.len() as i64,
    })
}

pub fn is_removable(path: &str, home: &str, shared_roots: &[&str]) -> bool {
    if home.is_empty()
        || !path.starts_with(&format!("{home}/"))
        || path.contains("/../")
        || path.ends_with("/..")
    {
        return false;
    }
    if !path.contains("/bazel/") {
        return false;
    }
    if shared_roots.contains(&path) {
        return false;
    }
    if path.ends_with("/cache") || path.ends_with("/install") {
        return false;
    }
    let path_parts = path.split('/').filter(|s| !s.is_empty()).count();
    let home_parts = home.split('/').filter(|s| !s.is_empty()).count();
    path_parts >= home_parts + 3
}

pub fn judge_cleanup(
    place: Option<&Value>,
    pr: Option<&Value>,
    status_result: Option<&Value>,
    mode: &str,
) -> Value {
    let (Some(pl), Some(p)) = (
        place.filter(|v| v.is_object()),
        pr.filter(|v| v.is_object()),
    ) else {
        return json!({ "cleanup": "none", "note": "" });
    };
    if mode == "off" || p.get("state").and_then(|v| v.as_str()) != Some("MERGED") {
        return json!({ "cleanup": "none", "note": "" });
    }
    let default_branch = pl
        .get("defaultBranch")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .unwrap_or("main");
    let pr_base = p.get("base").and_then(|v| v.as_str()).unwrap_or("");
    if pr_base != default_branch {
        return json!({
            "cleanup": "none",
            "note": format!("merged into {pr_base}, not {default_branch}"),
        });
    }
    if !pl
        .get("isLinked")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
    {
        return json!({
            "cleanup": "none",
            "note": "main checkout: nothing to remove",
        });
    }

    let mut ok = true;
    let mut out = String::new();
    match status_result {
        Some(Value::String(s)) => {
            out = s.trim().to_string();
        }
        Some(Value::Object(obj)) => {
            ok = obj.get("ok").and_then(|v| v.as_bool()) != Some(false);
            out = obj
                .get("out")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim()
                .to_string();
        }
        _ => {}
    }
    if !ok {
        return json!({ "cleanup": "blocked", "note": "git status failed" });
    }
    if !out.is_empty() {
        return json!({ "cleanup": "blocked", "note": "uncommitted changes" });
    }
    let place_head = pl.get("head").and_then(|v| v.as_str()).unwrap_or("");
    let pr_head = p.get("head").and_then(|v| v.as_str()).unwrap_or("");
    if place_head != pr_head {
        return json!({
            "cleanup": "blocked",
            "note": "local commits the pull request does not have",
        });
    }
    json!({ "cleanup": "ready", "note": "" })
}

pub fn total_cache_kb(caches: Option<&[Value]>) -> Option<f64> {
    let Some(arr) = caches else {
        return Some(0.0);
    };
    for c in arr {
        if let Some(obj) = c.as_object() {
            match obj.get("kb") {
                None | Some(Value::Null) => return None,
                _ => {}
            }
        }
    }
    let sum: f64 = arr
        .iter()
        .filter_map(|c| c.get("kb").and_then(|v| v.as_f64()))
        .filter(|v| v.is_finite())
        .sum();
    Some(sum)
}

pub fn summarise_worktrees(worktrees: Option<&[Value]>) -> Value {
    let mut items: Vec<Value> = worktrees
        .unwrap_or(&[])
        .iter()
        .filter(|w| w.is_object())
        .cloned()
        .collect();

    items.sort_by(|a, b| {
        let a_done = a.get("cleanup").and_then(|v| v.as_str()) == Some("done");
        let b_done = b.get("cleanup").and_then(|v| v.as_str()) == Some("done");
        if a_done != b_done {
            return if a_done {
                std::cmp::Ordering::Greater
            } else {
                std::cmp::Ordering::Less
            };
        }
        let a_ready = a.get("cleanup").and_then(|v| v.as_str()) == Some("ready");
        let b_ready = b.get("cleanup").and_then(|v| v.as_str()) == Some("ready");
        if a_ready != b_ready {
            return if a_ready {
                std::cmp::Ordering::Less
            } else {
                std::cmp::Ordering::Greater
            };
        }
        let a_key = a
            .get("branch")
            .or_else(|| a.get("root"))
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let b_key = b
            .get("branch")
            .or_else(|| b.get("root"))
            .and_then(|v| v.as_str())
            .unwrap_or("");
        a_key.cmp(b_key)
    });

    let mut linked = 0i64;
    let mut ready_count = 0i64;
    let mut blocked_count = 0i64;
    let mut cleaned_count = 0i64;
    let mut failing_prs = 0i64;
    let mut merged_prs = 0i64;
    let mut total_tree_kb = 0.0f64;
    let mut total_bazel_kb = 0.0f64;
    let mut reclaimable_kb = 0.0f64;

    for w in &items {
        if w.get("isLinked").and_then(|v| v.as_bool()).unwrap_or(false) {
            linked += 1;
        }
        let cleanup = w.get("cleanup").and_then(|v| v.as_str()).unwrap_or("");
        match cleanup {
            "ready" => ready_count += 1,
            "blocked" => blocked_count += 1,
            "done" => cleaned_count += 1,
            _ => {}
        }

        if let Some(pr) = w.get("pr").filter(|v| v.is_object()) {
            let pr_state = pr.get("state").and_then(|v| v.as_str()).unwrap_or("");
            if pr_state == "MERGED" {
                merged_prs += 1;
            }
            if pr_state != "MERGED"
                && pr_state != "CLOSED"
                && pr
                    .get("checks")
                    .and_then(|c| c.get("failed"))
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0)
                    > 0
            {
                failing_prs += 1;
            }
        }

        if cleanup != "done" {
            let t_kb = w
                .get("treeKb")
                .and_then(|v| v.as_f64())
                .filter(|v| v.is_finite())
                .unwrap_or(0.0);
            let b_kb = total_cache_kb(
                w.get("caches")
                    .and_then(|v| v.as_array())
                    .map(|v| v.as_slice()),
            )
            .unwrap_or(0.0);
            total_tree_kb += t_kb;
            total_bazel_kb += b_kb;
            if cleanup == "ready" {
                reclaimable_kb += t_kb + b_kb;
            }
        }
    }

    json!({
        "items": items,
        "total": items.len() as i64,
        "linked": linked,
        "readyCount": ready_count,
        "blockedCount": blocked_count,
        "cleanedCount": cleaned_count,
        "failingPrs": failing_prs,
        "mergedPrs": merged_prs,
        "totalTreeKb": total_tree_kb as i64,
        "totalBazelKb": total_bazel_kb as i64,
        "reclaimableKb": reclaimable_kb as i64,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::openui::{
        compile_to_html, escape_html, openui_literal, parse_openui_lang, resolve_data_path,
        to_openui_lang, RenderOptions,
    };

    #[test]
    fn fmt_size_formats_kb_mb_gb_and_unknown_values() {
        assert_eq!(fmt_size(None), "…");
        assert_eq!(fmt_size(Some(f64::NAN)), "…");
        assert_eq!(fmt_size(Some(0.0)), "0 KB");
        assert_eq!(fmt_size(Some(512.0)), "512 KB");
        assert_eq!(fmt_size(Some(1024.0)), "1 MB");
        assert_eq!(fmt_size(Some(256.0 * 1024.0)), "256 MB");
        assert_eq!(fmt_size(Some(1024.0 * 1024.0)), "1.0 GB");
        assert_eq!(fmt_size(Some(2.5 * 1024.0 * 1024.0)), "2.5 GB");
    }

    #[test]
    fn count_checks_tallies_check_runs_and_commit_statuses() {
        assert_eq!(
            count_checks(Some(&[])),
            json!({ "passed": 0, "failed": 0, "running": 0, "total": 0 })
        );
        assert_eq!(
            count_checks(None),
            json!({ "passed": 0, "failed": 0, "running": 0, "total": 0 })
        );
        let rollup = vec![
            json!({ "status": "COMPLETED", "conclusion": "SUCCESS" }),
            json!({ "status": "COMPLETED", "conclusion": "SKIPPED" }),
            json!({ "status": "COMPLETED", "conclusion": "NEUTRAL" }),
            json!({ "status": "IN_PROGRESS", "conclusion": null }),
            json!({ "status": "QUEUED", "conclusion": null }),
            json!({ "status": "COMPLETED", "conclusion": "FAILURE" }),
            json!({ "state": "SUCCESS" }),
            json!({ "state": "PENDING" }),
            json!({ "state": "ERROR" }),
        ];
        assert_eq!(
            count_checks(Some(&rollup)),
            json!({ "passed": 4, "failed": 2, "running": 3, "total": 9 })
        );
    }

    #[test]
    fn is_removable_guards_shared_bazel_roots_and_paths() {
        let home = "/Users/alice";
        let shared = [
            "/Users/alice/Library/Caches/bazel/_bazel_alice",
            "/Users/alice/.cache/bazel/_bazel_alice",
        ];
        assert!(is_removable(
            "/Users/alice/Library/Caches/bazel/_bazel_alice/0123456789abcdef0123456789abcdef",
            home,
            &shared
        ));
        assert!(is_removable(
            "/Users/alice/.cache/bazel/_bazel_alice/worktree-feat-x",
            home,
            &shared
        ));
        assert!(!is_removable(shared[0], home, &shared));
        assert!(!is_removable(
            &format!("{}/cache", shared[0]),
            home,
            &shared
        ));
        assert!(!is_removable(
            &format!("{}/install", shared[0]),
            home,
            &shared
        ));
        assert!(!is_removable(
            &format!("{}/../_bazel_alice/hash", shared[0]),
            home,
            &shared
        ));
        assert!(!is_removable("/tmp/bazel/_bazel_alice/hash", home, &shared));
        assert!(!is_removable(
            "/Users/alice/Workspace/project/sub/dir",
            home,
            &shared
        ));
        assert!(!is_removable("/Users/alice/bazel/short", home, &shared));
    }

    #[test]
    fn judge_cleanup_evaluates_worktree_safety() {
        let place = json!({
            "root": "/ws/worktrees/feat-a",
            "mainRoot": "/ws/main",
            "isLinked": true,
            "branch": "feat-a",
            "head": "sha-123",
            "defaultBranch": "main"
        });
        let merged_pr = json!({
            "number": 42,
            "state": "MERGED",
            "base": "main",
            "head": "sha-123"
        });

        assert_eq!(
            judge_cleanup(
                Some(&place),
                Some(&merged_pr),
                Some(&json!({ "ok": true, "out": "" })),
                "ask"
            ),
            json!({ "cleanup": "ready", "note": "" })
        );
        assert_eq!(
            judge_cleanup(
                Some(&place),
                Some(&merged_pr),
                Some(&json!({ "ok": true, "out": "" })),
                "off"
            ),
            json!({ "cleanup": "none", "note": "" })
        );
        assert_eq!(
            judge_cleanup(
                Some(&place),
                Some(
                    &json!({ "number": 42, "state": "MERGED", "base": "release-1.0", "head": "sha-123" })
                ),
                Some(&json!({ "ok": true, "out": "" })),
                "ask"
            ),
            json!({ "cleanup": "none", "note": "merged into release-1.0, not main" })
        );
        assert_eq!(
            judge_cleanup(
                Some(&place),
                Some(&merged_pr),
                Some(&json!({ "ok": false, "out": "" })),
                "ask"
            ),
            json!({ "cleanup": "blocked", "note": "git status failed" })
        );
        assert_eq!(
            judge_cleanup(
                Some(&place),
                Some(&merged_pr),
                Some(&json!({ "ok": true, "out": " M file.txt" })),
                "ask"
            ),
            json!({ "cleanup": "blocked", "note": "uncommitted changes" })
        );
    }

    #[test]
    fn summarise_worktrees_and_openui_rendering() {
        assert_eq!(
            total_cache_kb(Some(&[
                json!({ "path": "a", "kb": 100 }),
                json!({ "path": "b", "kb": 200 })
            ])),
            Some(300.0)
        );
        assert_eq!(
            total_cache_kb(Some(&[
                json!({ "path": "a", "kb": 100 }),
                json!({ "path": "b", "kb": null })
            ])),
            None
        );

        let sample = json!({
            "version": "0.1.0",
            "worktrees": [
                {
                    "root": "/ws/wt-1",
                    "branch": "feat-alpha",
                    "isLinked": true,
                    "pr": {
                        "number": 101,
                        "state": "MERGED",
                        "checks": { "passed": 5, "failed": 0, "running": 0, "total": 5 }
                    },
                    "treeKb": 2048,
                    "caches": [{ "path": "/cache/1", "kb": 4096 }],
                    "cleanup": "ready",
                    "note": ""
                },
                {
                    "root": "/ws/wt-2",
                    "branch": "fix-beta",
                    "isLinked": true,
                    "pr": {
                        "number": 102,
                        "state": "OPEN",
                        "checks": { "passed": 2, "failed": 1, "running": 0, "total": 3 }
                    },
                    "treeKb": 1024,
                    "caches": [],
                    "cleanup": "none",
                    "note": ""
                }
            ]
        });

        let dsl = to_openui_lang(Some(&sample));
        assert!(dsl.starts_with("# worktree-band state as OpenUI Lang v0.5\nroot = Card(["));
        let parsed = parse_openui_lang(&dsl, &json!({}));
        assert_eq!(
            parsed.root["args"][0][0]["args"],
            json!(["Worktree Band", "v0.1.0", "1 ready to clean", "success"])
        );

        let html = compile_to_html(
            "root = Card([TextContent(\"<img src=x onerror=alert(1)> & 'q'\")])",
            &json!({}),
            &RenderOptions {
                title: "<b>t</b>".to_string(),
                footer: "\"f\"".to_string(),
                ..RenderOptions::default()
            },
        );
        assert!(html.starts_with("<!DOCTYPE html>"));
        assert!(!html.contains("<img src=x"));
        assert!(html.contains("&lt;img src=x onerror=alert(1)&gt; &amp; &#39;q&#39;"));
        assert_eq!(escape_html(&Value::Null), "");
        assert_eq!(openui_literal(&json!("a\nb")), "\"a\\nb\"");
        let ctx = json!({ "data": { "rows": [{ "month": "Jan" }, { "month": "Feb" }] } });
        assert_eq!(
            resolve_data_path(&ctx, "data.rows.month"),
            Some(json!(["Jan", "Feb"]))
        );
    }
}
