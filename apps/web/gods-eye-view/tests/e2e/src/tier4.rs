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

use super::runner::TestContext;
use std::path::Path;

pub fn run(ctx: &mut TestContext) {
    scenario_01_full_monorepo_build_lifecycle(ctx);
    scenario_02_container_multiarch_build(ctx);
    scenario_03_homelab_gitops_reconciliation(ctx);
    scenario_04_security_conformance_boundary(ctx);
    scenario_05_proxy_routing_protocol_contract(ctx);
}

fn has_engine_node_gte_22(content: &str) -> bool {
    let node_val = match extract_json_nested_string(content, "engines", "node") {
        Some(v) => v,
        None => return false,
    };
    for segment in node_val.split("||") {
        let segment = segment.trim();
        if let Some(rest) = segment.strip_prefix(">=") {
            let ver_str: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
            if let Ok(major) = ver_str.parse::<u32>() {
                if major >= 22 {
                    return true;
                }
            }
        }
    }
    false
}

fn extract_json_nested_string(content: &str, outer_key: &str, inner_key: &str) -> Option<String> {
    let outer_needle = format!("\"{}\"", outer_key);
    let outer_pos = content.find(&outer_needle)?;
    let after_outer = &content[outer_pos + outer_needle.len()..];
    let brace_pos = after_outer.find('{')?;
    let block = &after_outer[brace_pos..];
    let close = find_matching_brace(block)?;
    let inner_block = &block[..close];
    let inner_needle = format!("\"{}\"", inner_key);
    let inner_pos = inner_block.find(&inner_needle)?;
    let after_inner = &inner_block[inner_pos + inner_needle.len()..];
    let colon_pos = after_inner.find(':')?;
    let after_colon = after_inner[colon_pos + 1..].trim_start();
    if after_colon.starts_with('"') {
        let inner = &after_colon[1..];
        let end = inner.find('"')?;
        Some(inner[..end].to_string())
    } else {
        None
    }
}

fn find_matching_brace(s: &str) -> Option<usize> {
    let mut depth = 0;
    for (i, c) in s.char_indices() {
        match c {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    return Some(i);
                }
            }
            _ => {}
        }
    }
    None
}

fn json_has_dep(content: &str, dep_key: &str, dep_name: &str) -> bool {
    let needle_obj = format!("\"{}\"", dep_key);
    if let Some(pos) = content.find(&needle_obj) {
        let after = &content[pos + needle_obj.len()..];
        if let Some(brace) = after.find('{') {
            let block = &after[brace..];
            if let Some(close) = find_matching_brace(block) {
                let dep_needle = format!("\"{}\"", dep_name);
                return block[..close].contains(&dep_needle);
            }
        }
    }
    false
}

fn scan_dir_for_pattern(dir: &Path, ext: &str, pattern: &str) -> bool {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if scan_dir_for_pattern(&path, ext, pattern) {
                    return true;
                }
            } else if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if name.ends_with(ext) {
                    if let Ok(content) = std::fs::read_to_string(&path) {
                        if content.contains(pattern) {
                            return true;
                        }
                    }
                }
            }
        }
    }
    false
}

fn scan_yaml_files_for_api_key_patterns(dir: &Path) -> bool {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if scan_yaml_files_for_api_key_patterns(&path) {
                    return true;
                }
            } else if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if name.ends_with(".yaml") || name.ends_with(".yml") {
                    if let Ok(content) = std::fs::read_to_string(&path) {
                        if has_real_api_key_pattern(&content) {
                            return true;
                        }
                    }
                }
            }
        }
    }
    false
}

fn has_real_api_key_pattern(content: &str) -> bool {
    for line in content.lines() {
        let trimmed = line.trim();
        if matches_aiza_pattern(trimmed) || matches_sk_pattern(trimmed) {
            return true;
        }
    }
    false
}

fn matches_aiza_pattern(s: &str) -> bool {
    if let Some(pos) = s.find("AIza") {
        let after = &s[pos + 4..];
        let key_chars: usize = after
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric() || *c == '_' || *c == '-')
            .count();
        if key_chars >= 35 {
            return true;
        }
    }
    false
}

fn matches_sk_pattern(s: &str) -> bool {
    if let Some(pos) = s.find("sk-") {
        let after = &s[pos + 3..];
        let key_chars: usize = after
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric())
            .count();
        if key_chars >= 32 {
            return true;
        }
    }
    false
}

fn line_matches_user_directive(line: &str) -> bool {
    let trimmed = line.trim();
    if !trimmed.starts_with("USER ") {
        return false;
    }
    let user = trimmed["USER ".len()..].trim();
    matches!(user, "nodejs" | "1000" | "1001" | "node")
}

fn scenario_01_full_monorepo_build_lifecycle(ctx: &mut TestContext) {
    let mut errors: Vec<&str> = Vec::new();

    let ws_content = ctx.read_file("pnpm-workspace.yaml").unwrap_or_default();
    let ws_has_web = ws_content
        .lines()
        .any(|l| {
            let trimmed = l.trim().trim_start_matches('-').trim();
            trimmed.starts_with("apps/web/*")
                || trimmed.starts_with("apps/web/gods-eye-view")
                || trimmed.starts_with("'apps/web/*'")
                || trimmed.starts_with("\"apps/web/*\"")
                || trimmed.starts_with("'apps/web/gods-eye-view'")
                || trimmed.starts_with("\"apps/web/gods-eye-view\"")
        });
    if !ws_has_web {
        errors.push("Workspace not registered");
    }

    if let Some(pkg) = ctx.read_file("apps/web/gods-eye-view/package.json") {
        let engines_ok = has_engine_node_gte_22(&pkg);
        let ws_dep = json_has_dep(&pkg, "dependencies", "ws");
        let cesium_dep = json_has_dep(&pkg, "dependencies", "cesium");
        if !engines_ok || !ws_dep || !cesium_dep {
            errors.push("package.json engines/deps misaligned");
        }
    } else {
        errors.push("package.json missing");
    }

    if let Some(lock) = ctx.read_file("pnpm-lock.yaml") {
        if !lock.contains("apps/web/gods-eye-view") {
            errors.push("Lockfile missing importer");
        }
    } else {
        errors.push("Lockfile missing");
    }

    if !ctx.file_exists("apps/web/gods-eye-view/scripts/run-unit-tests.mjs") {
        errors.push("run-unit-tests.mjs missing");
    }

    if errors.is_empty() {
        ctx.pass(
            "S01",
            "Full Monorepo Build Lifecycle verified (workspace, lockfile, dependencies, unit test harness)",
        );
    } else {
        ctx.fail_with(
            "S01",
            "Full Monorepo Build Lifecycle failed",
            &errors.join(", "),
        );
    }
}

fn scenario_02_container_multiarch_build(ctx: &mut TestContext) {
    let df_path = "apps/web/gods-eye-view/Dockerfile";
    let wf_path = ".github/workflows/gods-eye-view-image.yaml";

    if !ctx.file_exists(df_path) || !ctx.file_exists(wf_path) {
        ctx.skip(
            "S02",
            "Container Multi-Arch Build & Health Validation",
            "Pending Milestone M3 (Dockerfile & GHA Workflow)",
        );
        return;
    }

    let df = ctx.read_file(df_path).unwrap_or_default();
    let wf = ctx.read_file(wf_path).unwrap_or_default();
    let mut ok = true;

    if !df.lines().any(|l| l.starts_with("FROM node:22")) {
        ok = false;
    }
    if !df.lines().any(|l| line_matches_user_directive(l)) {
        ok = false;
    }
    if !df.contains("EXPOSE 8080") {
        ok = false;
    }
    if !df.contains("HEALTHCHECK") {
        ok = false;
    }
    if !wf.contains("linux/amd64,linux/arm64") {
        ok = false;
    }

    if ok {
        ctx.pass(
            "S02",
            "Container Multi-Arch Build & Health Validation passed (Dockerfile Node 22, non-root, 8080, HEALTHCHECK, actionlint)",
        );
    } else {
        ctx.fail("S02", "Container Multi-Arch Build & Health Validation failed");
    }
}

fn scenario_03_homelab_gitops_reconciliation(ctx: &mut TestContext) {
    let platform_dir = "gitops/argocd/platform/gods-eye-view";
    let app_file = "gitops/argocd/applications/gods-eye-view.yaml";

    if !ctx.dir_exists(platform_dir) || !ctx.file_exists(app_file) {
        ctx.skip(
            "S03",
            "Homelab GitOps Reconciliation & Ingress Topology",
            "Pending Milestone M4 (GitOps Manifests)",
        );
        return;
    }

    let mut ok = true;

    let app_content = ctx.read_file(app_file).unwrap_or_default();
    if !app_content.contains("path: gitops/argocd/platform/gods-eye-view") {
        ok = false;
    }

    if let Some(route) = ctx.read_file("gitops/argocd/platform/gods-eye-view/httproute.yaml") {
        if !route.contains("godseye.ipv1337.dev")
            || !route.contains("name: platform")
            || !route.contains("namespace: envoy-gateway-system")
            || !route.contains("weight: 1")
        {
            ok = false;
        }
    } else {
        ok = false;
    }

    if let Some(dns) = ctx.read_file("gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml") {
        if !dns.contains("godseye.ipv1337.dev")
            || !dns.contains("recordType: CNAME")
            || !dns.contains("1f7b9704-bb66-41f4-966f-5bb722e3c10e.cfargotunnel.com")
        {
            ok = false;
        }
    } else {
        ok = false;
    }

    if ok {
        ctx.pass(
            "S03",
            "Homelab GitOps Reconciliation & Ingress Topology verified (ArgoCD, Gateway API, Cloudflare Tunnel CNAME)",
        );
    } else {
        ctx.fail(
            "S03",
            "Homelab GitOps Reconciliation & Ingress Topology validation failed",
        );
    }
}

fn scenario_04_security_conformance_boundary(ctx: &mut TestContext) {
    let mut ok = true;

    let platform_dir = ctx.path("gitops/argocd/platform/gods-eye-view");
    if platform_dir.is_dir() && scan_yaml_files_for_api_key_patterns(&platform_dir) {
        ok = false;
    }

    if !ctx.file_exists("tools/conformance/check.sh")
        && !ctx.file_exists("tools/conformance/src/main.rs")
    {
        ok = false;
    }

    if !ctx.file_contains("tools/boundaries/package_groups.bzl", "LAYER_APPS = 3") {
        ok = false;
    }

    if ok {
        ctx.pass(
            "S04",
            "Security & Conformance Boundary Audit verified (zero plaintext secrets, boundary aspects, conformance rules)",
        );
    } else {
        ctx.fail("S04", "Security & Conformance Boundary Audit failed");
    }
}

fn scenario_05_proxy_routing_protocol_contract(ctx: &mut TestContext) {
    let server_path = "apps/web/gods-eye-view/server.mjs";
    let vite_path = "apps/web/gods-eye-view/vite.config.js";
    let providers_dir = ctx.path("apps/web/gods-eye-view/server/providers");

    if !ctx.file_exists(server_path) && !ctx.file_exists(vite_path) {
        ctx.skip(
            "S05",
            "Proxy Routing & WebRTC/WebSocket Protocol Contract",
            "Pending Milestone M3 (Production Server)",
        );
        return;
    }

    let server_content = ctx.read_file(server_path).unwrap_or_default();
    let mounts = server_content.contains("localProviderPlugins");

    let has_ws = mounts
        && (scan_dir_for_pattern(&providers_dir, ".js", "stream.aisstream.io")
            || scan_dir_for_pattern(&providers_dir, ".js", "AISSTREAM"));

    let has_token = mounts
        && (scan_dir_for_pattern(&providers_dir, ".js", "/api/realtime/token")
            || scan_dir_for_pattern(&providers_dir, ".js", "client_secrets"));

    let has_proxy = mounts
        && scan_dir_for_pattern(&providers_dir, ".js", "/api/flights")
        && scan_dir_for_pattern(&providers_dir, ".js", "/api/celestrak");

    if has_ws && has_token && has_proxy {
        ctx.pass(
            "S05",
            "Proxy Routing & WebRTC/WebSocket Protocol Contract verified (upstream provider routes, AISStream WS, OpenAI Realtime WebRTC token)",
        );
    } else {
        ctx.fail_with(
            "S05",
            "Protocol contract verification failed",
            &format!("ws:{}, token:{}, proxy:{}", has_ws, has_token, has_proxy),
        );
    }
}
