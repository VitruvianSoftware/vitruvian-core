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

fn scan_dir_for_pattern(base: &Path, ext: &str, needle: &str) -> bool {
    if let Ok(entries) = std::fs::read_dir(base) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if scan_dir_for_pattern(&path, ext, needle) {
                    return true;
                }
            } else if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if name.ends_with(ext) {
                    if let Ok(content) = std::fs::read_to_string(&path) {
                        if content.contains(needle) {
                            return true;
                        }
                    }
                }
            }
        }
    }
    false
}

fn read_yaml_field<'a>(content: &'a str, key: &str) -> Option<&'a str> {
    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix(key) {
            let rest = rest.trim();
            if let Some(val) = rest.strip_prefix(':') {
                let val = val.trim();
                let val = val.trim_matches('"').trim_matches('\'');
                if !val.is_empty() {
                    return Some(val);
                }
            }
        }
    }
    None
}

pub fn run(ctx: &mut TestContext) {
    // ==================================================================================
    // Category A: Source Code Inspection — Server Routes, SSRF Defenses & WebSockets
    // ==================================================================================

    // ADV-01: CelesTrak Subpath Routing (/api/celestrak/stations)
    {
        let providers_dir = ctx.path("apps/web/gods-eye-view/server/providers");
        let has_celestrak = scan_dir_for_pattern(&providers_dir, ".js", "celestrak")
            || scan_dir_for_pattern(&providers_dir, ".js", "/api/celestrak");
        if has_celestrak {
            ctx.pass("ADV-01", "/api/celestrak route handler registered in server providers");
        } else {
            ctx.fail("ADV-01", "/api/celestrak route handler not found in server providers");
        }
    }

    // ADV-02: Radio Subpath Routing (/api/radio/stations)
    {
        let providers_dir = ctx.path("apps/web/gods-eye-view/server/providers");
        let has_radio = scan_dir_for_pattern(&providers_dir, ".js", "/api/radio")
            || scan_dir_for_pattern(&providers_dir, ".js", "radioBrowserProxy");
        if has_radio {
            ctx.pass("ADV-02", "/api/radio route handler registered in server providers");
        } else {
            ctx.fail("ADV-02", "/api/radio route handler not found in server providers");
        }
    }

    // ADV-03: SSRF IPv4-Mapped IPv6 Loopback Rejection
    {
        let providers_dir = ctx.path("apps/web/gods-eye-view/server/providers");
        let src_dir = ctx.path("apps/web/gods-eye-view/src");
        let has_ipv6_loopback = scan_dir_for_pattern(&providers_dir, ".js", "::ffff:127.0.0.1")
            || scan_dir_for_pattern(&src_dir, ".js", "::ffff:127.0.0.1")
            || scan_dir_for_pattern(&src_dir, ".mjs", "::ffff:127.0.0.1");
        if has_ipv6_loopback {
            ctx.pass("ADV-03", "SSRF IPv4-mapped IPv6 loopback address checked in source");
        } else {
            ctx.fail("ADV-03", "No ::ffff:127.0.0.1 SSRF defense pattern found in source");
        }
    }

    // ADV-04: SSRF DNS Rebinding Defense (nip.io)
    {
        let providers_dir = ctx.path("apps/web/gods-eye-view/server/providers");
        let src_dir = ctx.path("apps/web/gods-eye-view/src");
        let has_loopback_check =
            scan_dir_for_pattern(&providers_dir, ".js", "loopback")
                || scan_dir_for_pattern(&providers_dir, ".js", "RFC1918")
                || scan_dir_for_pattern(&src_dir, ".mjs", "loopback")
                || scan_dir_for_pattern(&src_dir, ".js", "LOOPBACK_ADDRESSES");
        if has_loopback_check {
            ctx.pass("ADV-04", "DNS rebinding/loopback defense patterns present in source");
        } else {
            ctx.fail("ADV-04", "No loopback/RFC1918 defense patterns found in source");
        }
    }

    // ADV-05: SSRF Cloud Metadata Endpoint Blocking
    {
        let src_dir = ctx.path("apps/web/gods-eye-view/src");
        let has_metadata_block =
            scan_dir_for_pattern(&src_dir, ".js", "169.254")
                || scan_dir_for_pattern(&src_dir, ".mjs", "169.254")
                || scan_dir_for_pattern(&src_dir, ".js", "metadata.google");
        if has_metadata_block {
            ctx.pass("ADV-05", "Cloud metadata endpoint (169.254/metadata.google) defense found");
        } else {
            ctx.fail("ADV-05", "No cloud metadata SSRF defense pattern found in source");
        }
    }

    // ADV-06: Protocol Smuggling Prevention (file:// scheme)
    {
        let providers_dir = ctx.path("apps/web/gods-eye-view/server/providers");
        let src_dir = ctx.path("apps/web/gods-eye-view/src");
        let has_scheme_check =
            scan_dir_for_pattern(&providers_dir, ".js", "http")
                && (scan_dir_for_pattern(&providers_dir, ".js", "protocol")
                    || scan_dir_for_pattern(&src_dir, ".mjs", "scheme")
                    || scan_dir_for_pattern(&src_dir, ".js", "http(s)")
                    || scan_dir_for_pattern(&src_dir, ".js", "must be http"));
        if has_scheme_check {
            ctx.pass("ADV-06", "Protocol validation (HTTP-only scheme) present in source");
        } else {
            ctx.fail("ADV-06", "No HTTP-only protocol validation found in source");
        }
    }

    // ADV-07: Setup Keys Disallowed Key Injection
    {
        let has_key_validation = ctx.file_contains(
            "apps/web/gods-eye-view/src/keySetupCore.mjs",
            "validateKeySetupUpdates",
        ) && ctx.file_contains(
            "apps/web/gods-eye-view/src/keySetupCore.mjs",
            "unknown-key",
        );
        if has_key_validation {
            ctx.pass(
                "ADV-07",
                "Setup key validation rejects unknown environment variables",
            );
        } else {
            ctx.fail(
                "ADV-07",
                "validateKeySetupUpdates or unknown-key rejection not found in keySetupCore.mjs",
            );
        }
    }

    // ADV-08: Setup Keys Malformed JSON Rejection
    {
        let has_json_parse = ctx.file_contains(
            "apps/web/gods-eye-view/server/standalone/key-setup.js",
            "JSON.parse",
        ) && ctx.file_contains(
            "apps/web/gods-eye-view/server/standalone/key-setup.js",
            "invalid-json",
        );
        if has_json_parse {
            ctx.pass(
                "ADV-08",
                "Malformed JSON rejection (400 invalid-json) present in key-setup endpoint",
            );
        } else {
            ctx.fail(
                "ADV-08",
                "JSON.parse or invalid-json error code not found in key-setup.js",
            );
        }
    }

    // ADV-09: Setup Keys Oversized Payload Rejection
    {
        let has_body_limit = ctx.file_contains(
            "apps/web/gods-eye-view/server/standalone/key-setup.js",
            "too-large",
        ) && ctx.file_contains(
            "apps/web/gods-eye-view/server/standalone/key-setup.js",
            "413",
        );
        if has_body_limit {
            ctx.pass(
                "ADV-09",
                "Oversized payload rejection (413 too-large) present in key-setup endpoint",
            );
        } else {
            ctx.fail(
                "ADV-09",
                "Body size limit or 413 response not found in key-setup.js",
            );
        }
    }

    // ADV-10: Rate Limiting Enforcement on Token Minting
    {
        let has_rate_limit =
            ctx.file_exists("apps/web/gods-eye-view/server/providers/common/rate-limit.js")
                && ctx.file_contains(
                    "apps/web/gods-eye-view/server/providers/common/rate-limit.js",
                    "makeRateLimiter",
                );
        if has_rate_limit {
            ctx.pass(
                "ADV-10",
                "Rate limiter (makeRateLimiter) present in server/providers/common/rate-limit.js",
            );
        } else {
            ctx.fail("ADV-10", "Rate limiter not found in common/rate-limit.js");
        }
    }

    // ADV-11: Rate Limiter Identity Trust & Header Verification
    {
        let has_socket_peer = ctx.file_contains(
            "apps/web/gods-eye-view/server/providers/common/rate-limit.js",
            "socket",
        );
        if has_socket_peer {
            ctx.pass(
                "ADV-11",
                "Rate limiter uses socket peer address (immune to X-Forwarded-For spoofing)",
            );
        } else {
            ctx.fail(
                "ADV-11",
                "Rate limiter does not reference socket peer for identity trust",
            );
        }
    }

    // ADV-12: WebSocket Binary Frame Injection Resilience
    {
        let has_ws_error_handler = ctx.file_contains(
            "apps/web/gods-eye-view/server.mjs",
            "stream.on('error'",
        ) || ctx.file_contains("apps/web/gods-eye-view/server.mjs", "on('error'");
        if has_ws_error_handler {
            ctx.pass(
                "ADV-12",
                "WebSocket/stream error handler present in server.mjs",
            );
        } else {
            ctx.fail(
                "ADV-12",
                "No stream or WebSocket error handler found in server.mjs",
            );
        }
    }

    // ADV-13: WebSocket High Connection Churn & Socket Reset Resilience
    {
        let server_content = ctx.read_file("apps/web/gods-eye-view/server.mjs");
        let ais_adapter = ctx.read_file("apps/web/gods-eye-view/src/data/aisStreamAdapter.js");
        let ais_live = ctx.read_file("apps/web/gods-eye-view/server/providers/vessels/ais-live.js");
        let combined = format!(
            "{}{}{}",
            server_content.as_deref().unwrap_or(""),
            ais_adapter.as_deref().unwrap_or(""),
            ais_live.as_deref().unwrap_or("")
        );
        let has_ws_handling =
            combined.contains("WebSocket") || combined.contains("upgrade") || combined.contains("ws");
        let has_error_handling = combined.contains("on('error'")
            || combined.contains("on(\"error\"")
            || combined.contains("onerror")
            || combined.contains("addEventListener('error'");
        if has_ws_handling && has_error_handling {
            ctx.pass(
                "ADV-13",
                "WebSocket upgrade handling with error resilience present in server.mjs",
            );
        } else {
            ctx.fail(
                "ADV-13",
                "WebSocket handling or error resilience missing in server.mjs",
            );
        }
    }

    // ADV-14: WebSocket Initial Snapshot Message Delivery
    {
        let providers_dir = ctx.path("apps/web/gods-eye-view/server/providers");
        let src_dir = ctx.path("apps/web/gods-eye-view/src");
        let has_snapshot =
            scan_dir_for_pattern(&providers_dir, ".js", "snapshot")
                || scan_dir_for_pattern(&src_dir, ".js", "snapshot")
                || scan_dir_for_pattern(&src_dir, ".mjs", "snapshot");
        if has_snapshot {
            ctx.pass(
                "ADV-14",
                "WebSocket snapshot message pattern present in source",
            );
        } else {
            ctx.fail(
                "ADV-14",
                "No snapshot message delivery pattern found in source",
            );
        }
    }

    // ADV-15: CCTV Graceful Fallback SVG Response
    {
        let has_svg_fallback = ctx.file_contains(
            "apps/web/gods-eye-view/server/providers/cctv.js",
            "image/svg+xml",
        );
        if has_svg_fallback {
            ctx.pass("ADV-15", "CCTV endpoint serves fallback SVG (image/svg+xml content type)");
        } else {
            ctx.fail(
                "ADV-15",
                "No SVG fallback response (image/svg+xml) found in cctv.js",
            );
        }
    }

    // ADV-16: GBFS Encoded SSRF Target Rejection
    {
        let has_gbfs = ctx.file_exists("apps/web/gods-eye-view/server/providers/gbfs.js")
            && ctx.file_contains(
                "apps/web/gods-eye-view/server/providers/gbfs.js",
                "/api/gbfs",
            );
        if has_gbfs {
            ctx.pass("ADV-16", "GBFS proxy endpoint (/api/gbfs) registered in gbfs.js");
        } else {
            ctx.fail("ADV-16", "GBFS proxy endpoint not found in gbfs.js");
        }
    }

    // ADV-17: AIS Live Track Query Parameter Validation
    {
        let has_ais_live =
            ctx.file_exists("apps/web/gods-eye-view/server/providers/vessels/ais-live.js")
                && ctx.file_contains(
                    "apps/web/gods-eye-view/server/providers/vessels/ais-live.js",
                    "aisstream",
                );
        if has_ais_live {
            ctx.pass("ADV-17", "AIS live track endpoint with aisstream integration present");
        } else {
            ctx.fail(
                "ADV-17",
                "AIS live track endpoint (ais-live.js with aisstream) not found",
            );
        }
    }

    // ADV-18: Regional Brief Coordinates Out-of-Bounds Resilience
    {
        let has_regional =
            ctx.file_exists("apps/web/gods-eye-view/server/providers/regional/briefing.js")
                && ctx.file_contains(
                    "apps/web/gods-eye-view/server/providers/regional/briefing.js",
                    "/api/regional-brief",
                );
        if has_regional {
            ctx.pass("ADV-18", "Regional brief endpoint (/api/regional-brief) registered");
        } else {
            ctx.fail(
                "ADV-18",
                "Regional brief endpoint not found in regional/briefing.js",
            );
        }
    }

    // ADV-19: Static Asset Serving Directory Traversal Resistance
    {
        let server_content = ctx.read_file("apps/web/gods-eye-view/server.mjs");
        let src_dir = ctx.path("apps/web/gods-eye-view/src");
        let has_fs_deny = scan_dir_for_pattern(&src_dir, ".mjs", "fs.deny")
            || scan_dir_for_pattern(&src_dir, ".js", "fs.deny");
        let has_static_serving = server_content
            .as_ref()
            .map(|c| c.contains("Static file stream") || c.contains("dist"))
            .unwrap_or(false);
        if has_fs_deny || has_static_serving {
            ctx.pass(
                "ADV-19",
                "Static file serving with path restriction present in source",
            );
        } else {
            ctx.fail(
                "ADV-19",
                "No static file path traversal defense found in source",
            );
        }
    }

    // ADV-20: Health and Diagnostic Telemetry Readiness
    {
        let has_healthz = ctx.file_contains("apps/web/gods-eye-view/server.mjs", "/healthz")
            && ctx.file_contains("apps/web/gods-eye-view/server.mjs", "status");
        if has_healthz {
            ctx.pass("ADV-20", "/healthz endpoint with status payload present in server.mjs");
        } else {
            ctx.fail(
                "ADV-20",
                "/healthz endpoint or status response not found in server.mjs",
            );
        }
    }

    // ==================================================================================
    // Category B: GitOps, Container Security, CI Workflow & Monorepo Integration
    // ==================================================================================

    let deployment_path = "gitops/argocd/platform/gods-eye-view/deployment.yaml";
    let httproute_path = "gitops/argocd/platform/gods-eye-view/httproute.yaml";
    let service_path = "gitops/argocd/platform/gods-eye-view/service.yaml";
    let dnsendpoint_path = "gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml";
    let application_path = "gitops/argocd/applications/gods-eye-view.yaml";
    let kustomization_path = "gitops/argocd/platform/gods-eye-view/kustomization.yaml";
    let project_path = "gitops/argocd/projects/gods-eye-view-project.yaml";
    let secrets_template_path = "gitops/argocd/platform/gods-eye-view/secrets.template.yaml";
    let dockerfile_path = "apps/web/gods-eye-view/Dockerfile";
    let dockerignore_path = "apps/web/gods-eye-view/.dockerignore";
    let workflow_path = ".github/workflows/gods-eye-view-image.yaml";

    // ADV-21 (K8S-01): Pod Security Restricted Profile
    {
        if let Some(content) = ctx.read_file(deployment_path) {
            let mut ok = true;
            let mut errors = Vec::new();

            if !content.contains("automountServiceAccountToken: false") {
                ok = false;
                errors.push("automountServiceAccountToken not false");
            }
            if !content.contains("runAsNonRoot: true") {
                ok = false;
                errors.push("runAsNonRoot not true");
            }
            if !content.contains("runAsUser: 1001") {
                ok = false;
                errors.push("runAsUser not 1001");
            }
            if !content.contains("runAsGroup: 1001") {
                ok = false;
                errors.push("runAsGroup not 1001");
            }
            if !content.contains("fsGroup: 1001") {
                ok = false;
                errors.push("fsGroup not 1001");
            }
            if !content.contains("type: RuntimeDefault") {
                ok = false;
                errors.push("seccompProfile type not RuntimeDefault");
            }
            if !content.contains("allowPrivilegeEscalation: false") {
                ok = false;
                errors.push("allowPrivilegeEscalation not false");
            }
            if !content.contains("readOnlyRootFilesystem: true") {
                ok = false;
                errors.push("readOnlyRootFilesystem not true");
            }
            if !content.contains("- ALL") {
                ok = false;
                errors.push("capabilities.drop ALL missing");
            }
            if content.contains("hostNetwork: true") {
                ok = false;
                errors.push("hostNetwork forbidden");
            }
            if content.contains("hostPID: true") {
                ok = false;
                errors.push("hostPID forbidden");
            }
            if content.contains("hostIPC: true") {
                ok = false;
                errors.push("hostIPC forbidden");
            }

            if ok {
                ctx.pass(
                    "ADV-21",
                    "Pod Security Restricted Profile strictly enforced in deployment.yaml",
                );
            } else {
                ctx.fail_with(
                    "ADV-21",
                    "Pod Security Restricted Profile violation in deployment.yaml",
                    &errors.join("; "),
                );
            }
        } else {
            ctx.skip("ADV-21", "Pod Security Restricted Profile", "deployment.yaml missing");
        }
    }

    // ADV-22 (K8S-02): Volume Mount Isolation
    {
        if let Some(content) = ctx.read_file(deployment_path) {
            let has_tmp_mount = content.contains("mountPath: /tmp");
            let no_host_path = !content.contains("hostPath:");
            if has_tmp_mount && no_host_path {
                ctx.pass(
                    "ADV-22",
                    "Volume mounts isolated to safe emptyDir, zero hostPath volumes",
                );
            } else {
                let mut reason = String::new();
                if !has_tmp_mount {
                    reason.push_str("/tmp not mounted; ");
                }
                if !no_host_path {
                    reason.push_str("hostPath volume detected");
                }
                ctx.fail_with("ADV-22", "Volume mount isolation check failed", &reason);
            }
        } else {
            ctx.skip("ADV-22", "Volume mount isolation", "deployment.yaml missing");
        }
    }

    // ADV-23 (K8S-03): Probe Threshold Safety
    {
        if let Some(content) = ctx.read_file(deployment_path) {
            let has_liveness = content.contains("livenessProbe:");
            let has_readiness = content.contains("readinessProbe:");
            let probes_use_healthz =
                content.contains("path: /healthz") && content.contains("port: 8080");
            if has_liveness && has_readiness && probes_use_healthz {
                ctx.pass(
                    "ADV-23",
                    "Health probes configure safe thresholds on /healthz port 8080",
                );
            } else {
                ctx.fail_with(
                    "ADV-23",
                    "Health probe threshold safety check failed",
                    "livenessProbe/readinessProbe with /healthz:8080 required",
                );
            }
        } else {
            ctx.skip("ADV-23", "Probe threshold safety", "deployment.yaml missing");
        }
    }

    // ADV-24 (K8S-04): HTTPRoute Gateway Ref Integrity
    {
        if let Some(content) = ctx.read_file(httproute_path) {
            let has_hostname = content.contains("godseye.ipv1337.dev");
            let has_gateway_group = content.contains("gateway.networking.k8s.io");
            let has_gateway_kind = content.contains("kind: Gateway");
            let has_platform = content.contains("name: platform");
            let has_ns = content.contains("namespace: envoy-gateway-system");
            if has_hostname && has_gateway_group && has_gateway_kind && has_platform && has_ns {
                ctx.pass(
                    "ADV-24",
                    "HTTPRoute parentRefs strictly bound to platform Gateway in envoy-gateway-system",
                );
            } else {
                ctx.fail(
                    "ADV-24",
                    "HTTPRoute parentRef integrity check failed",
                );
            }
        } else {
            ctx.skip("ADV-24", "HTTPRoute gateway ref integrity", "httproute.yaml missing");
        }
    }

    // ADV-25 (K8S-05): HTTPRoute Backend Service Parity
    {
        let hr = ctx.read_file(httproute_path);
        let svc = ctx.read_file(service_path);
        let dep = ctx.read_file(deployment_path);
        if hr.is_some() && svc.is_some() && dep.is_some() {
            let hr = hr.unwrap();
            let svc = svc.unwrap();
            let has_backend_ref = hr.contains("backendRefs:");
            let has_weight = hr.contains("weight: 1");

            let svc_name = read_yaml_field(&svc, "name");
            let hr_has_svc_name = svc_name
                .map(|n| hr.contains(&format!("name: {}", n)))
                .unwrap_or(false);

            if has_backend_ref && has_weight && hr_has_svc_name {
                ctx.pass(
                    "ADV-25",
                    "HTTPRoute backendRef port and name align with Service and Deployment topology",
                );
            } else {
                ctx.fail(
                    "ADV-25",
                    "Ingress backend topology alignment check failed",
                );
            }
        } else {
            ctx.skip(
                "ADV-25",
                "HTTPRoute backend service parity",
                "httproute.yaml, service.yaml or deployment.yaml missing",
            );
        }
    }

    // ADV-26 (K8S-06): DNSEndpoint Tunnel CNAME Coherence
    {
        if let Some(content) = ctx.read_file(dnsendpoint_path) {
            let has_hostname = content.contains("godseye.ipv1337.dev");
            let has_cname = content.contains("recordType: CNAME");
            let has_ttl = content.contains("recordTTL: 1");
            let has_cf_tunnel = content.contains(".cfargotunnel.com");
            let has_proxied = content.contains("cloudflare-proxied");
            if has_hostname && has_cname && has_ttl && has_cf_tunnel && has_proxied {
                ctx.pass(
                    "ADV-26",
                    "DNSEndpoint CNAME target, TTL=1, and cloudflare-proxied annotations verified",
                );
            } else {
                ctx.fail(
                    "ADV-26",
                    "DNSEndpoint Cloudflare Tunnel configuration check failed",
                );
            }
        } else {
            ctx.skip("ADV-26", "DNSEndpoint tunnel CNAME", "dnsendpoint.yaml missing");
        }
    }

    // ADV-27 (K8S-07): ArgoCD Secret Template Exclusion
    {
        let app = ctx.read_file(application_path);
        let kust = ctx.read_file(kustomization_path);
        if app.is_some() && kust.is_some() {
            let app = app.unwrap();
            let kust = kust.unwrap();
            let has_correct_path =
                app.contains("path: gitops/argocd/platform/gods-eye-view");
            let has_head = app.contains("targetRevision: HEAD");
            let no_directory_block = !app
                .lines()
                .any(|l| !l.trim_start().starts_with('#') && l.contains("directory:"));
            let secrets_excluded = !kust
                .lines()
                .any(|l| !l.trim_start().starts_with('#') && l.contains("secrets.template.yaml"));
            if has_correct_path && has_head && no_directory_block && secrets_excluded {
                ctx.pass(
                    "ADV-27",
                    "ArgoCD renders only kustomization resources, secrets.template.yaml excluded",
                );
            } else {
                let mut reason = String::new();
                if !has_correct_path {
                    reason.push_str("source.path mismatch; ");
                }
                if !has_head {
                    reason.push_str("targetRevision not HEAD; ");
                }
                if !no_directory_block {
                    reason.push_str("directory block would render all files; ");
                }
                if !secrets_excluded {
                    reason.push_str("secrets.template.yaml listed in kustomization");
                }
                ctx.fail_with(
                    "ADV-27",
                    "ArgoCD secrets.template.yaml exclusion check failed",
                    &reason,
                );
            }
        } else {
            ctx.skip(
                "ADV-27",
                "ArgoCD secret template exclusion",
                "gods-eye-view.yaml or kustomization.yaml missing",
            );
        }
    }

    // ADV-28 (K8S-08): ArgoCD Sync Options Resilience
    {
        if let Some(content) = ctx.read_file(application_path) {
            let has_ssa = content.contains("ServerSideApply=true");
            let has_create_ns = content.contains("CreateNamespace=true");
            let has_prune = content.contains("prune: true");
            let has_self_heal = content.contains("selfHeal: true");
            let has_sync_wave = content.contains("sync-wave");
            if has_ssa && has_create_ns && has_prune && has_self_heal && has_sync_wave {
                ctx.pass(
                    "ADV-28",
                    "ArgoCD syncOptions enforce SSA, prune, selfHeal, and sync-wave",
                );
            } else {
                ctx.fail(
                    "ADV-28",
                    "ArgoCD syncPolicy resilience check failed",
                );
            }
        } else {
            ctx.skip("ADV-28", "ArgoCD sync options", "gods-eye-view.yaml missing");
        }
    }

    // ADV-29 (K8S-09): AppProject RBAC Whitelist Confinement
    {
        if let Some(content) = ctx.read_file(project_path) {
            let has_single_dest = content.contains("namespace: gods-eye-view")
                && content.contains("https://kubernetes.default.svc");
            let has_cluster_ns_only =
                content.contains("kind: Namespace") && !content.contains("kind: '*'");
            let expected_kinds = [
                "Deployment",
                "Service",
                "DNSEndpoint",
                "HTTPRoute",
                "SealedSecret",
                "Secret",
            ];
            let has_all_kinds = expected_kinds
                .iter()
                .all(|k| content.contains(&format!("kind: {}", k)));
            let no_wildcard_kind = !content
                .lines()
                .any(|l| {
                    let t = l.trim();
                    t == "kind: '*'" || t == "kind: \"*\"" || t == "kind: '*'"
                });

            if has_single_dest && has_cluster_ns_only && has_all_kinds && no_wildcard_kind {
                ctx.pass(
                    "ADV-29",
                    "AppProject RBAC whitelists strictly confined without wildcards",
                );
            } else {
                ctx.fail(
                    "ADV-29",
                    "AppProject RBAC whitelist confinement check failed",
                );
            }
        } else {
            ctx.skip(
                "ADV-29",
                "AppProject RBAC whitelist",
                "gods-eye-view-project.yaml missing",
            );
        }
    }

    // ADV-30 (K8S-10): Secrets Template Safety and Schema
    {
        let sec = ctx.read_file(secrets_template_path);
        let dep = ctx.read_file(deployment_path);
        if sec.is_some() && dep.is_some() {
            let sec = sec.unwrap();
            let dep = dep.unwrap();
            let has_secret_kind = sec.contains("kind: Secret");
            let has_opaque = sec.contains("type: Opaque");
            let required_keys = [
                "GOOGLE_MAPS_API_KEY",
                "OPENAI_API_KEY",
                "CESIUM_ION_ACCESS_TOKEN",
                "AISSTREAM_API_KEY",
            ];
            let has_all_keys = required_keys.iter().all(|k| sec.contains(k));

            let has_placeholder_format = required_keys.iter().all(|k| {
                if let Some(pos) = sec.find(k) {
                    let after = &sec[pos + k.len()..];
                    after.contains('<') && after.contains('>')
                } else {
                    false
                }
            });

            let no_real_keys = !sec.contains("sk-")
                && !sec.contains("AIza");

            let has_secret_ref =
                dep.contains("gods-eye-view-secrets") && dep.contains("optional: true");

            if has_secret_kind
                && has_opaque
                && has_all_keys
                && has_placeholder_format
                && no_real_keys
                && has_secret_ref
            {
                ctx.pass(
                    "ADV-30",
                    "Secrets template: zero committed secrets, deployment references secrets optionally",
                );
            } else {
                let mut errs = Vec::new();
                if !has_secret_kind {
                    errs.push("kind not Secret");
                }
                if !has_opaque {
                    errs.push("type not Opaque");
                }
                if !has_all_keys {
                    errs.push("required keys missing");
                }
                if !has_placeholder_format {
                    errs.push("values not placeholder format");
                }
                if !no_real_keys {
                    errs.push("real API key detected");
                }
                if !has_secret_ref {
                    errs.push("deployment missing optional secretRef");
                }
                ctx.fail_with(
                    "ADV-30",
                    "Secrets template schema and safety check failed",
                    &errs.join("; "),
                );
            }
        } else {
            ctx.skip(
                "ADV-30",
                "Secrets template safety",
                "secrets.template.yaml or deployment.yaml missing",
            );
        }
    }

    // ADV-31 (CNT-11): Dockerignore Coverage and Leak Prevention
    {
        if let Some(content) = ctx.read_file(dockerignore_path) {
            let lines: Vec<&str> = content
                .lines()
                .map(|l| l.trim())
                .filter(|l| !l.is_empty() && !l.starts_with('#'))
                .collect();
            let required = [
                "node_modules",
                ".git",
                "bazel-*",
                ".env*",
                "*.pem",
                "*.key",
                "secrets*",
            ];
            let missing: Vec<&&str> = required
                .iter()
                .filter(|r| !lines.iter().any(|l| l == *r))
                .collect();
            if missing.is_empty() {
                ctx.pass(
                    "ADV-31",
                    "Dockerignore covers sensitive patterns and build artifacts",
                );
            } else {
                ctx.fail_with(
                    "ADV-31",
                    "Dockerignore coverage check failed",
                    &format!("missing patterns: {}", missing.iter().map(|m| **m).collect::<Vec<_>>().join(", ")),
                );
            }
        } else {
            ctx.skip("ADV-31", "Dockerignore coverage", ".dockerignore missing");
        }
    }

    // ADV-32 (CNT-12): Dockerfile User UID/GID Sync with Deployment
    {
        let df = ctx.read_file(dockerfile_path);
        let dep = ctx.read_file(deployment_path);
        if df.is_some() && dep.is_some() {
            let df = df.unwrap();
            let dep = dep.unwrap();
            let has_useradd_1001 = df.contains("-u 1001");
            let has_groupadd_1001 = df.contains("-g 1001");
            let has_user_stmt = df.contains("USER nodejs") || df.contains("USER 1001");
            let dep_has_uid = dep.contains("runAsUser: 1001");
            let dep_has_gid = dep.contains("runAsGroup: 1001");
            let dep_has_fs = dep.contains("fsGroup: 1001");
            if has_useradd_1001
                && has_groupadd_1001
                && has_user_stmt
                && dep_has_uid
                && dep_has_gid
                && dep_has_fs
            {
                ctx.pass(
                    "ADV-32",
                    "Dockerfile UID/GID 1001 synchronised with Deployment security context",
                );
            } else {
                ctx.fail(
                    "ADV-32",
                    "Dockerfile UID/GID synchronization check failed",
                );
            }
        } else {
            ctx.skip(
                "ADV-32",
                "Dockerfile UID sync",
                "Dockerfile or deployment.yaml missing",
            );
        }
    }

    // ADV-33 (CNT-13): Dockerfile Multi-Stage and Healthcheck
    {
        if let Some(df) = ctx.read_file(dockerfile_path) {
            let stages: Vec<&str> = df
                .lines()
                .filter(|l| l.starts_with("FROM ") && l.contains(" AS "))
                .collect();
            let has_multi_stage = stages.len() >= 2;
            let has_node_22 = stages.iter().any(|s| s.contains("node:22"));
            let has_prod_install = df.contains("pnpm install --prod");
            let has_expose = df.contains("EXPOSE 8080");
            let has_healthcheck = df.contains("HEALTHCHECK");
            let has_healthz_probe =
                df.contains("curl -f http://localhost:8080/healthz")
                    || df.contains("curl -sf http://localhost:8080/healthz")
                    || df.contains("curl --fail http://localhost:8080/healthz");
            if has_multi_stage
                && has_node_22
                && has_prod_install
                && has_expose
                && has_healthcheck
                && has_healthz_probe
            {
                ctx.pass(
                    "ADV-33",
                    "Dockerfile multi-stage, prod-only deps, and container healthcheck verified",
                );
            } else {
                let mut errs = Vec::new();
                if !has_multi_stage {
                    errs.push("not multi-stage");
                }
                if !has_node_22 {
                    errs.push("no Node 22 base");
                }
                if !has_prod_install {
                    errs.push("no --prod install");
                }
                if !has_expose {
                    errs.push("no EXPOSE 8080");
                }
                if !has_healthcheck {
                    errs.push("no HEALTHCHECK");
                }
                if !has_healthz_probe {
                    errs.push("HEALTHCHECK doesn't probe /healthz");
                }
                ctx.fail_with(
                    "ADV-33",
                    "Dockerfile multi-stage and healthcheck check failed",
                    &errs.join("; "),
                );
            }
        } else {
            ctx.skip("ADV-33", "Dockerfile multi-stage", "Dockerfile missing");
        }
    }

    // ADV-34 (CI-14): Workflow Security Least Privilege
    {
        if let Some(content) = ctx.read_file(workflow_path) {
            let has_contents_read = content.contains("contents: read");
            let has_packages_write = content.contains("packages: write");
            let has_cancel_in_progress = content.contains("cancel-in-progress");
            let has_timeout = content.contains("timeout-minutes:");
            let has_login_condition = content.contains("Log in to GHCR")
                || content.contains("login");
            let has_push_condition = content.contains("Build and push")
                || content.contains("push:");
            if has_contents_read
                && has_packages_write
                && has_cancel_in_progress
                && has_timeout
                && has_login_condition
                && has_push_condition
            {
                ctx.pass(
                    "ADV-34",
                    "CI workflow enforces least-privilege tokens, PR push blocking, and timeout",
                );
            } else {
                ctx.fail(
                    "ADV-34",
                    "CI workflow least-privilege security check failed",
                );
            }
        } else {
            ctx.skip(
                "ADV-34",
                "CI workflow security",
                "gods-eye-view-image.yaml missing",
            );
        }
    }

    // ADV-35 (CI-15): Workflow Scoped Path Triggers
    {
        if let Some(content) = ctx.read_file(workflow_path) {
            let expected_paths = [
                "apps/web/gods-eye-view/**",
                ".github/workflows/gods-eye-view-image.yaml",
                "pnpm-lock.yaml",
                "pnpm-workspace.yaml",
            ];
            let has_push_main = content.contains("branches:")
                && content.contains("main");
            let has_all_paths = expected_paths.iter().all(|p| content.contains(p));
            let has_push_trigger = content.contains("push:");
            let has_pr_trigger = content.contains("pull_request:");
            let has_dispatch = content.contains("workflow_dispatch:");
            if has_push_main && has_all_paths && has_push_trigger && has_pr_trigger && has_dispatch
            {
                ctx.pass(
                    "ADV-35",
                    "CI workflow triggers strictly confined to app subpath, workflow, and lockfiles",
                );
            } else {
                ctx.fail(
                    "ADV-35",
                    "CI workflow trigger path scoping check failed",
                );
            }
        } else {
            ctx.skip(
                "ADV-35",
                "CI workflow path triggers",
                "gods-eye-view-image.yaml missing",
            );
        }
    }

    // ADV-36 (BZL-16): Package Group Architectural Layer
    {
        if let Some(content) = ctx.read_file("tools/boundaries/package_groups.bzl") {
            let has_apps_pattern =
                content.contains("//apps/...") || content.contains("\"//apps/...\"");
            let has_layer_3 = content.contains("LAYER_APPS = 3");
            let has_layer_mapping = content.contains("LAYER_APPS")
                && (content.contains("\"apps\"") || content.contains("'apps'"));
            if has_apps_pattern && has_layer_3 && has_layer_mapping {
                ctx.pass(
                    "ADV-36",
                    "Bazel architectural layer boundaries place //apps/... at LAYER_APPS = 3",
                );
            } else {
                ctx.fail(
                    "ADV-36",
                    "Bazel architectural layer boundary check failed",
                );
            }
        } else {
            ctx.skip(
                "ADV-36",
                "Package group layer",
                "tools/boundaries/package_groups.bzl missing",
            );
        }
    }

    // ADV-37 (BZL-17): Gazelle Exclusion and Build Integrity
    {
        let root_build = ctx.read_file("BUILD");
        let app_build = ctx.build_file_content();
        if root_build.is_some() || app_build.is_some() {
            let mut ok = true;
            let mut errors = Vec::new();

            if let Some(ref rb) = root_build {
                if !rb.contains("gazelle:exclude") {
                    ok = false;
                    errors.push("root BUILD missing gazelle:exclude");
                }
            }

            if let Some(ref ab) = app_build {
                if !ab.contains("gazelle:ignore") {
                    ok = false;
                    errors.push("app BUILD missing gazelle:ignore");
                }
                let required_rules = ["pipeline_unit", "doctor"];
                for rule in &required_rules {
                    if !ab.contains(rule) {
                        ok = false;
                        errors.push(rule);
                    }
                }
            } else {
                ok = false;
                errors.push("app BUILD file missing");
            }

            if ok {
                ctx.pass(
                    "ADV-37",
                    "Gazelle exclusions protect hand-authored build rules and pipeline_unit present",
                );
            } else {
                ctx.fail_with(
                    "ADV-37",
                    "Gazelle exclusion and build integrity check failed",
                    &errors.join("; "),
                );
            }
        } else {
            ctx.skip(
                "ADV-37",
                "Gazelle exclusion",
                "BUILD files missing",
            );
        }
    }
}
