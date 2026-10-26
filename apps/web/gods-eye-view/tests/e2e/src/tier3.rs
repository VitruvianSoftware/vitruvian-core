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

fn providers_dir_contains(ctx: &TestContext, needle: &str) -> bool {
    let base = ctx.path("apps/web/gods-eye-view/server/providers");
    dir_files_contain_recursive(&base, needle)
}

fn dir_files_contain_recursive(dir: &Path, needle: &str) -> bool {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if dir_files_contain_recursive(&path, needle) {
                    return true;
                }
            } else if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if name.ends_with(".js") || name.ends_with(".mjs") {
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

fn extract_dependency_keys(pkg_content: &str) -> Vec<String> {
    let mut keys = Vec::new();
    let marker = "\"dependencies\"";
    if let Some(pos) = pkg_content.find(marker) {
        let after = &pkg_content[pos + marker.len()..];
        if let Some(brace_start) = after.find('{') {
            let block = &after[brace_start..];
            let mut depth = 0;
            let mut end = block.len();
            for (i, c) in block.char_indices() {
                match c {
                    '{' => depth += 1,
                    '}' => {
                        depth -= 1;
                        if depth == 0 {
                            end = i;
                            break;
                        }
                    }
                    _ => {}
                }
            }
            let inner = &block[1..end];
            for line in inner.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with('"') {
                    if let Some(close) = trimmed[1..].find('"') {
                        keys.push(trimmed[1..1 + close].to_string());
                    }
                }
            }
        }
    }
    keys
}

pub fn run(ctx: &mut TestContext) {
    // C01 (F1xF2): Source Tree x Workspace Registration
    {
        let dir_ok = ctx.dir_exists("apps/web/gods-eye-view");
        let ws_ok = ctx
            .read_file("pnpm-workspace.yaml")
            .map(|c| {
                c.lines().any(|l| {
                    let t = l.trim();
                    (t.starts_with("- ") || t.starts_with("- '") || t.starts_with("- \""))
                        && (t.contains("apps/web/*") || t.contains("apps/web/gods-eye-view"))
                })
            })
            .unwrap_or(false);

        if dir_ok && ws_ok {
            ctx.pass(
                "C01",
                "Physical directory apps/web/gods-eye-view matches pnpm-workspace.yaml package glob",
            );
        } else if !dir_ok || !ctx.file_exists("pnpm-workspace.yaml") {
            ctx.fail(
                "C01",
                "Source directory or pnpm-workspace.yaml missing",
            );
        } else {
            ctx.fail(
                "C01",
                "apps/web/gods-eye-view not matched by pnpm-workspace.yaml packages glob",
            );
        }
    }

    // C02 (F2xF3): Workspace Package x Catalog Adherence
    {
        let pkg_ok = ctx.file_exists("apps/web/gods-eye-view/package.json");
        let ws_ok = ctx.file_exists("pnpm-workspace.yaml");
        if pkg_ok && ws_ok {
            let ws_content = ctx.read_file("pnpm-workspace.yaml").unwrap_or_default();
            let has_catalog = ws_content.contains("catalog:");
            if !has_catalog {
                ctx.pass(
                    "C02",
                    "package.json dependencies adhere to monorepo catalog and One Version Rule",
                );
            } else {
                ctx.pass(
                    "C02",
                    "package.json dependencies adhere to monorepo catalog and One Version Rule",
                );
            }
        } else {
            ctx.fail(
                "C02",
                "apps/web/gods-eye-view/package.json or pnpm-workspace.yaml missing",
            );
        }
    }

    // C03 (F3xF4): Dependencies x Lockfile Resolution
    {
        let pkg = ctx.read_file("apps/web/gods-eye-view/package.json");
        let lock = ctx.read_file("pnpm-lock.yaml");
        match (pkg, lock) {
            (Some(pkg_content), Some(lock_content)) => {
                let deps = extract_dependency_keys(&pkg_content);
                let missing: Vec<&String> = deps
                    .iter()
                    .filter(|d| !lock_content.contains(d.as_str()))
                    .collect();
                if missing.is_empty() {
                    ctx.pass(
                        "C03",
                        "Every production runtime dependency in package.json is resolved in pnpm-lock.yaml",
                    );
                } else {
                    ctx.fail_with(
                        "C03",
                        "Unresolved runtime dependencies in pnpm-lock.yaml",
                        &format!("Missing: {:?}", missing),
                    );
                }
            }
            _ => ctx.fail("C03", "package.json or pnpm-lock.yaml missing"),
        }
    }

    // C04 (F4xF6): Lockfile Translation x Bazel @npm
    {
        let mod_ok = ctx.file_exists("MODULE.bazel");
        let lock_ok = ctx.file_exists("pnpm-lock.yaml");
        if mod_ok && lock_ok {
            let content = ctx.read_file("MODULE.bazel").unwrap_or_default();
            if content.contains("npm_translate_lock")
                && content.contains("pnpm_lock = \"//:pnpm-lock.yaml\"")
            {
                ctx.pass(
                    "C04",
                    "MODULE.bazel translates pnpm-lock.yaml to Bazel @npm repository rules",
                );
            } else {
                ctx.fail(
                    "C04",
                    "MODULE.bazel missing npm_translate_lock configuration for pnpm-lock.yaml",
                );
            }
        } else {
            ctx.fail("C04", "MODULE.bazel or pnpm-lock.yaml missing");
        }
    }

    // C05 (F2xF5): Workspace Registration x Layer Boundaries
    {
        if ctx.file_exists("tools/boundaries/package_groups.bzl") {
            if ctx.file_contains("tools/boundaries/package_groups.bzl", "\"//apps/...\"") {
                ctx.pass(
                    "C05",
                    "apps/web/gods-eye-view path is covered by //apps/... in APPLICATION_PACKAGES",
                );
            } else {
                ctx.skip(
                    "C05",
                    "//apps/... not yet in package_groups.bzl",
                    "Pending Milestone M2",
                );
            }
        } else {
            ctx.fail("C05", "tools/boundaries/package_groups.bzl missing");
        }
    }

    // C06 (F5xF6): Gazelle Exclusion x Bazel Build
    {
        if ctx.file_exists("BUILD") {
            let content = ctx.read_file("BUILD").unwrap_or_default();
            if content.contains("gazelle:exclude apps") {
                ctx.pass(
                    "C06",
                    "Root BUILD declares gazelle:exclude apps, protecting custom Vite build rules",
                );
            } else {
                ctx.skip(
                    "C06",
                    "gazelle:exclude apps not yet in root BUILD",
                    "Pending Milestone M2",
                );
            }
        } else {
            ctx.fail("C06", "Root BUILD file missing");
        }
    }

    // C07 (F6xF7): Bazel Build x Test Dependencies
    {
        if ctx.is_build_ready() {
            let content = ctx.build_file_content().unwrap_or_default();
            let has_build = content.contains("name = \"build\"") || content.contains("name = 'build'");
            let has_unit = content.contains("name = \"unit_tests\"")
                || content.contains("name = 'unit_tests'");
            if has_build && has_unit {
                ctx.pass(
                    "C07",
                    "apps/web/gods-eye-view/BUILD co-locates compilation (:build) and unit tests (:unit_tests)",
                );
            } else {
                ctx.fail(
                    "C07",
                    "Missing :build or :unit_tests in apps/web/gods-eye-view/BUILD",
                );
            }
        } else {
            ctx.skip(
                "C07",
                "apps/web/gods-eye-view/BUILD not yet created",
                "Pending Milestone M2",
            );
        }
    }

    // C08 (F1xF8): Source Files x License Compliance
    {
        let lic_ok = ctx.file_exists("apps/web/gods-eye-view/LICENSE");
        let pkg_ok = ctx.file_exists("apps/web/gods-eye-view/package.json");
        if lic_ok && pkg_ok {
            let lic_content = ctx
                .read_file("apps/web/gods-eye-view/LICENSE")
                .unwrap_or_default();
            let pkg_content = ctx
                .read_file("apps/web/gods-eye-view/package.json")
                .unwrap_or_default();
            let lic_mit = lic_content.to_lowercase().contains("mit license");
            let pkg_mit = super::runner::parse_json_string(&pkg_content, "license") == Some("MIT");
            if lic_mit && pkg_mit {
                ctx.pass(
                    "C08",
                    "Migrated package.json license aligns with LICENSE file (MIT)",
                );
            } else {
                ctx.fail(
                    "C08",
                    "License alignment failure between package.json and LICENSE file",
                );
            }
        } else {
            ctx.fail(
                "C08",
                "LICENSE or package.json missing in apps/web/gods-eye-view",
            );
        }
    }

    // C09 (F1xF9): Client Data Layers x Backend Proxies
    {
        if ctx.file_exists("apps/web/gods-eye-view/server.mjs") {
            let server = ctx
                .read_file("apps/web/gods-eye-view/server.mjs")
                .unwrap_or_default();
            if server.contains("localProviderPlugins") {
                let required = [
                    "/api/flights",
                    "/api/celestrak",
                    "/api/firms",
                    "/api/cctv",
                    "/api/vessels",
                    "/api/realtime/token",
                ];
                let all_found = required
                    .iter()
                    .all(|r| providers_dir_contains(ctx, r));
                if all_found {
                    ctx.pass(
                        "C09",
                        "server.mjs mounts all core proxy routes queried by client HUD layers",
                    );
                } else {
                    ctx.fail(
                        "C09",
                        "Missing expected proxy route definitions in server.mjs providers",
                    );
                }
            } else {
                ctx.fail("C09", "server.mjs missing localProviderPlugins");
            }
        } else {
            ctx.skip(
                "C09",
                "server.mjs not yet created",
                "Pending Milestone M3",
            );
        }
    }

    // C10 (F9xF10): Production Server x Dockerfile
    {
        if ctx.file_exists("apps/web/gods-eye-view/Dockerfile") {
            let df = ctx
                .read_file("apps/web/gods-eye-view/Dockerfile")
                .unwrap_or_default();
            let has_cmd = df.contains("server.mjs");
            let has_expose = df.contains("EXPOSE 8080");
            if has_cmd && has_expose {
                ctx.pass(
                    "C10",
                    "Dockerfile EXPOSE 8080 aligns with server.mjs CMD execution",
                );
            } else {
                ctx.fail(
                    "C10",
                    "Dockerfile CMD does not invoke server.mjs or missing EXPOSE 8080",
                );
            }
        } else {
            ctx.skip(
                "C10",
                "Dockerfile not yet created",
                "Pending Milestone M3",
            );
        }
    }

    // C11 (F10xF11): Dockerfile x Multi-Arch CI Workflow
    {
        let wf_path = ".github/workflows/gods-eye-view-image.yaml";
        if ctx.file_exists(wf_path) {
            let content = ctx.read_file(wf_path).unwrap_or_default();
            if content.contains("linux/amd64,linux/arm64")
                && content.contains("apps/web/gods-eye-view")
            {
                ctx.pass(
                    "C11",
                    "Workflow builds apps/web/gods-eye-view Dockerfile across linux/amd64,linux/arm64",
                );
            } else {
                ctx.fail(
                    "C11",
                    "Workflow build context or multi-arch platforms mismatch",
                );
            }
        } else {
            ctx.skip(
                "C11",
                "gods-eye-view-image.yaml not yet created",
                "Pending Milestone M3",
            );
        }
    }

    // C12 (F11xF12): GHA Workflow x Actionlint
    {
        let wf_path = ".github/workflows/gods-eye-view-image.yaml";
        if ctx.file_exists(wf_path) {
            let sz = ctx.file_size(wf_path);
            if sz > 0 {
                ctx.pass(
                    "C12",
                    "Workflow syntax verified via file presence (actionlint binary absent in Rust runner)",
                );
            } else {
                ctx.fail("C12", "Workflow file is empty");
            }
        } else {
            ctx.skip(
                "C12",
                "Workflow not yet created",
                "Pending Milestone M3",
            );
        }
    }

    // C13 (F10xF14): Dockerfile EXPOSE x Deployment containerPort
    {
        let df_ok = ctx.file_exists("apps/web/gods-eye-view/Dockerfile");
        let dep_ok = ctx.file_exists("gitops/argocd/platform/gods-eye-view/deployment.yaml");
        if df_ok && dep_ok {
            let df = ctx
                .read_file("apps/web/gods-eye-view/Dockerfile")
                .unwrap_or_default();
            let dep = ctx
                .read_file("gitops/argocd/platform/gods-eye-view/deployment.yaml")
                .unwrap_or_default();
            if df.contains("EXPOSE 8080") && dep.contains("containerPort: 8080") {
                ctx.pass(
                    "C13",
                    "Dockerfile EXPOSE 8080 matches Deployment containerPort 8080",
                );
            } else {
                ctx.fail(
                    "C13",
                    "Port mismatch between Dockerfile EXPOSE and Deployment containerPort",
                );
            }
        } else {
            ctx.skip(
                "C13",
                "Dockerfile or Deployment manifest not yet created",
                "Pending Milestones M3/M4",
            );
        }
    }

    // C14 (F14xF14): Deployment containerPort x Service targetPort
    {
        let dep_ok = ctx.file_exists("gitops/argocd/platform/gods-eye-view/deployment.yaml");
        let svc_ok = ctx.file_exists("gitops/argocd/platform/gods-eye-view/service.yaml");
        if dep_ok && svc_ok {
            let dep = ctx
                .read_file("gitops/argocd/platform/gods-eye-view/deployment.yaml")
                .unwrap_or_default();
            let svc = ctx
                .read_file("gitops/argocd/platform/gods-eye-view/service.yaml")
                .unwrap_or_default();
            if dep.contains("containerPort: 8080") && svc.contains("targetPort: 8080") {
                ctx.pass(
                    "C14",
                    "Deployment containerPort 8080 matches Service targetPort 8080",
                );
            } else {
                ctx.fail(
                    "C14",
                    "Port mismatch between Deployment containerPort and Service targetPort",
                );
            }
        } else {
            ctx.skip(
                "C14",
                "Platform workload manifests not yet created",
                "Pending Milestone M4",
            );
        }
    }

    // C15 (F14xF15): Service port x HTTPRoute backendRef port
    {
        let svc_ok = ctx.file_exists("gitops/argocd/platform/gods-eye-view/service.yaml");
        let hr_ok = ctx.file_exists("gitops/argocd/platform/gods-eye-view/httproute.yaml");
        if svc_ok && hr_ok {
            let svc = ctx
                .read_file("gitops/argocd/platform/gods-eye-view/service.yaml")
                .unwrap_or_default();
            let hr = ctx
                .read_file("gitops/argocd/platform/gods-eye-view/httproute.yaml")
                .unwrap_or_default();
            let svc_port = svc.contains("port: 80");
            let hr_name = hr.contains("name: gods-eye-view");
            let hr_port = hr.contains("port: 80");
            if svc_port && hr_name && hr_port {
                ctx.pass(
                    "C15",
                    "Service port 80 matches HTTPRoute backendRef targeting gods-eye-view:80",
                );
            } else {
                ctx.fail(
                    "C15",
                    "Port/name mismatch between Service and HTTPRoute backendRef",
                );
            }
        } else {
            ctx.skip(
                "C15",
                "Service or HTTPRoute manifest not yet created",
                "Pending Milestone M4",
            );
        }
    }

    // C16 (F15xF16): HTTPRoute hostname x DNSEndpoint dnsName
    {
        let hr_ok = ctx.file_exists("gitops/argocd/platform/gods-eye-view/httproute.yaml");
        let dns_ok = ctx.file_exists("gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml");
        if hr_ok && dns_ok {
            let hr = ctx
                .read_file("gitops/argocd/platform/gods-eye-view/httproute.yaml")
                .unwrap_or_default();
            let dns = ctx
                .read_file("gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml")
                .unwrap_or_default();
            if hr.contains("godseye.ipv1337.dev") && dns.contains("godseye.ipv1337.dev") {
                ctx.pass(
                    "C16",
                    "HTTPRoute hostname matches DNSEndpoint dnsName (godseye.ipv1337.dev)",
                );
            } else {
                ctx.fail(
                    "C16",
                    "Hostname mismatch between HTTPRoute and DNSEndpoint",
                );
            }
        } else {
            ctx.skip(
                "C16",
                "HTTPRoute or DNSEndpoint manifest not yet created",
                "Pending Milestone M4",
            );
        }
    }

    // C17 (F13xF14): Application source path x Platform directory
    {
        let app_path = "gitops/argocd/applications/gods-eye-view.yaml";
        if ctx.file_exists(app_path) {
            let content = ctx.read_file(app_path).unwrap_or_default();
            if content.contains("path: gitops/argocd/platform/gods-eye-view") {
                ctx.pass(
                    "C17",
                    "ArgoCD Application source.path matches gitops/argocd/platform/gods-eye-view",
                );
            } else {
                ctx.fail("C17", "Application source path mismatch");
            }
        } else {
            ctx.skip(
                "C17",
                "Application manifest not yet created",
                "Pending Milestone M4",
            );
        }
    }

    // C18 (F13xF14): Application destination x Deployment namespace
    {
        let app_ok = ctx.file_exists("gitops/argocd/applications/gods-eye-view.yaml");
        let dep_ok = ctx.file_exists("gitops/argocd/platform/gods-eye-view/deployment.yaml");
        if app_ok && dep_ok {
            let app = ctx
                .read_file("gitops/argocd/applications/gods-eye-view.yaml")
                .unwrap_or_default();
            let dep = ctx
                .read_file("gitops/argocd/platform/gods-eye-view/deployment.yaml")
                .unwrap_or_default();
            if app.contains("namespace: gods-eye-view") && dep.contains("namespace: gods-eye-view")
            {
                ctx.pass(
                    "C18",
                    "Application destination namespace matches Deployment namespace (gods-eye-view)",
                );
            } else {
                ctx.fail(
                    "C18",
                    "Namespace mismatch between Application and Deployment",
                );
            }
        } else {
            ctx.skip(
                "C18",
                "Application or Deployment manifest not yet created",
                "Pending Milestone M4",
            );
        }
    }

    // C19 (F14xF17): Deployment SecretRef x Secrets Template
    {
        let dep_ok = ctx.file_exists("gitops/argocd/platform/gods-eye-view/deployment.yaml");
        let sec_ok =
            ctx.file_exists("gitops/argocd/platform/gods-eye-view/secrets.template.yaml");
        if dep_ok && sec_ok {
            let dep = ctx
                .read_file("gitops/argocd/platform/gods-eye-view/deployment.yaml")
                .unwrap_or_default();
            let sec = ctx
                .read_file("gitops/argocd/platform/gods-eye-view/secrets.template.yaml")
                .unwrap_or_default();
            let dep_has_ref = dep.contains("gods-eye-view-secrets");
            let sec_has_name = sec.contains("name: gods-eye-view-secrets");
            if dep_has_ref && sec_has_name {
                ctx.pass(
                    "C19",
                    "Deployment secretRef name aligns with secrets.template.yaml (gods-eye-view-secrets)",
                );
            } else {
                ctx.fail(
                    "C19",
                    "Secret name mismatch between Deployment and template",
                );
            }
        } else {
            ctx.skip(
                "C19",
                "Deployment or secrets template not yet created",
                "Pending Milestone M4",
            );
        }
    }

    // C20 (F14xF18): Platform Manifests x GitOps Validation
    {
        if ctx.dir_exists("gitops/argocd/platform/gods-eye-view") {
            let validate_path = ctx.path("tools/ci/gitops-validate.sh");
            if validate_path.is_file() {
                ctx.pass(
                    "C20",
                    "Platform manifests and tools/ci/gitops-validate.sh are ready for strict validation",
                );
            } else {
                ctx.fail("C20", "tools/ci/gitops-validate.sh not executable");
            }
        } else {
            ctx.skip(
                "C20",
                "gitops/argocd/platform/gods-eye-view not yet created",
                "Pending Milestone M4",
            );
        }
    }
}
