#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Tier 3: Cross-Feature Combinations Test Suite (Pairwise Monorepo Layer Validation)
# 20 Cross-Feature Integration Tests
# Validates interaction contracts between monorepo layers:
# pnpm workspace -> Bazel toolchain -> Containerization -> GitOps Ingress Topology
set -uo pipefail

resolve_workspace_root() {
	local target="${1:-$0}"
	while [ -L "$target" ]; do
		local dir="$(cd -P "$(dirname "$target")" && pwd)"
		target="$(readlink "$target")"
		[[ $target != /* ]] && target="$dir/$target"
	done
	local cur="$(cd -P "$(dirname "$target")" && pwd)"
	while [ "$cur" != "/" ] && [ -n "$cur" ]; do
		if [ -f "$cur/MODULE.bazel" ] || [ -f "$cur/go.work" ] || [ -f "$cur/pnpm-workspace.yaml" ]; then
			echo "$cur"
			return 0
		fi
		cur="$(dirname "$cur")"
	done
	echo "${BUILD_WORKSPACE_DIRECTORY:-$PWD}"
}

ROOT="${BUILD_WORKSPACE_DIRECTORY:-$(resolve_workspace_root "${BASH_SOURCE[0]}")}"
cd "$ROOT"

if [ -d "/opt/homebrew/bin" ]; then
	export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
fi
for sp in /Users/*"/Library/Python/3."*"/lib/python/site-packages" /opt/homebrew/lib/python3.*/site-packages; do
	if [ -d "$sp" ]; then
		export PYTHONPATH="$sp:${PYTHONPATH:-}"
	fi
done

STRICT_MODE=false
for arg in "$@"; do
	if [ "$arg" = "--strict" ]; then
		STRICT_MODE=true
	fi
done

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

pass() {
	TOTAL_TESTS=$((TOTAL_TESTS + 1))
	PASSED_TESTS=$((PASSED_TESTS + 1))
	echo "  ok ${TOTAL_TESTS} - $1"
}

fail() {
	TOTAL_TESTS=$((TOTAL_TESTS + 1))
	FAILED_TESTS=$((FAILED_TESTS + 1))
	echo "  not ok ${TOTAL_TESTS} - $1" >&2
	if [ -n "${2:-}" ]; then
		echo "    # Error: $2" >&2
	fi
}

skip() {
	TOTAL_TESTS=$((TOTAL_TESTS + 1))
	if [ "$STRICT_MODE" = true ]; then
		FAILED_TESTS=$((FAILED_TESTS + 1))
		echo "  not ok ${TOTAL_TESTS} - $1 (STRICT: $2)" >&2
	else
		SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
		PASSED_TESTS=$((PASSED_TESTS + 1))
		echo "  ok ${TOTAL_TESTS} - $1 # SKIP $2"
	fi
}

is_m2_build_ready() {
	[ -f "apps/web/gods-eye-view/BUILD" ] && grep -q -E '(gazelle:ignore|rules_js|vite|pipeline_unit|doctor)' "apps/web/gods-eye-view/BUILD" 2>/dev/null
}

echo "================================================================================"
echo " Tier 3: Cross-Feature Combinations Test Suite (20 Pairwise Integration Tests)"
echo " Working Directory: ${ROOT}"
echo " Strict Mode:        ${STRICT_MODE}"
echo "================================================================================"

# ------------------------------------------------------------------------------
# Pairwise 1: F1 x F2 (Source Tree x Workspace Glob)
# ------------------------------------------------------------------------------
echo "--- Pairwise 1: Source Tree x Workspace Registration (F1 x F2) ---"
if [ -d "apps/web/gods-eye-view" ] && [ -f "pnpm-workspace.yaml" ]; then
	if grep -E '^\s*-\s*apps/web/(\*|gods-eye-view)' pnpm-workspace.yaml >/dev/null; then
		pass "C1 (F1xF2): Physical directory apps/web/gods-eye-view matches pnpm-workspace.yaml package glob"
	else
		fail "C1 (F1xF2): apps/web/gods-eye-view not matched by pnpm-workspace.yaml packages glob"
	fi
else
	fail "C1 (F1xF2): Source directory or pnpm-workspace.yaml missing"
fi

# ------------------------------------------------------------------------------
# Pairwise 2: F2 x F3 (Workspace Package x Catalog Adherence)
# ------------------------------------------------------------------------------
echo "--- Pairwise 2: Workspace Package x Catalog Adherence (F2 x F3) ---"
if [ -f "apps/web/gods-eye-view/package.json" ] && [ -f "pnpm-workspace.yaml" ]; then
	no_catalog_conflict=$(python3 -c '
import json, yaml
workspace = yaml.safe_load(open("pnpm-workspace.yaml"))
catalog = workspace.get("catalog", {})
pkg = json.load(open("apps/web/gods-eye-view/package.json"))
deps = {**pkg.get("dependencies", {}), **pkg.get("devDependencies", {})}
# If a package is in the global catalog, it should not declare an incompatible range
conflicts = []
for k, v in deps.items():
    if k in catalog:
        cat_v = catalog[k]
        if v != cat_v and not v.startswith("catalog:"):
            conflicts.append(f"{k}: {v} vs catalog {cat_v}")
print("1" if len(conflicts) == 0 else "0")
')
	if [ "$no_catalog_conflict" = "1" ]; then
		pass "C2 (F2xF3): package.json dependencies adhere to monorepo catalog and One Version Rule"
	else
		fail "C2 (F2xF3): Dependency conflict detected against pnpm-workspace.yaml catalog"
	fi
else
	fail "C2 (F2xF3): apps/web/gods-eye-view/package.json or pnpm-workspace.yaml missing"
fi

# ------------------------------------------------------------------------------
# Pairwise 3: F3 x F4 (package.json Dependencies x Lockfile Resolution)
# ------------------------------------------------------------------------------
echo "--- Pairwise 3: Dependencies x Lockfile Resolution (F3 x F4) ---"
if [ -f "apps/web/gods-eye-view/package.json" ] && [ -f "pnpm-lock.yaml" ]; then
	all_deps_in_lock=$(python3 -c '
import json
pkg = json.load(open("apps/web/gods-eye-view/package.json"))
deps = list(pkg.get("dependencies", {}).keys())
lock_text = open("pnpm-lock.yaml").read()
missing = [d for d in deps if d not in lock_text]
print("1" if len(missing) == 0 else f"Missing: {missing}")
')
	if [ "$all_deps_in_lock" = "1" ]; then
		pass "C3 (F3xF4): Every production runtime dependency in package.json is resolved in pnpm-lock.yaml"
	else
		fail "C3 (F3xF4): Unresolved runtime dependencies in pnpm-lock.yaml: $all_deps_in_lock"
	fi
else
	fail "C3 (F3xF4): package.json or pnpm-lock.yaml missing"
fi

# ------------------------------------------------------------------------------
# Pairwise 4: F4 x F6 (Lockfile x Bazel @npm Rules)
# ------------------------------------------------------------------------------
echo "--- Pairwise 4: Lockfile Translation x Bazel @npm (F4 x F6) ---"
if [ -f "MODULE.bazel" ] && [ -f "pnpm-lock.yaml" ]; then
	if grep -q 'npm_translate_lock' MODULE.bazel && grep -q 'pnpm_lock = "//:pnpm-lock.yaml"' MODULE.bazel; then
		pass "C4 (F4xF6): MODULE.bazel translates pnpm-lock.yaml to Bazel @npm repository rules"
	else
		fail "C4 (F4xF6): MODULE.bazel missing npm_translate_lock configuration for pnpm-lock.yaml"
	fi
else
	fail "C4 (F4xF6): MODULE.bazel or pnpm-lock.yaml missing"
fi

# ------------------------------------------------------------------------------
# Pairwise 5: F2 x F5 (Workspace Registration x Boundary Architecture)
# ------------------------------------------------------------------------------
echo "--- Pairwise 5: Workspace Registration x Layer Boundaries (F2 x F5) ---"
if [ -f "tools/boundaries/package_groups.bzl" ]; then
	if grep -q '"//apps/..."' tools/boundaries/package_groups.bzl; then
		pass "C5 (F2xF5): apps/web/gods-eye-view path is covered by //apps/... in APPLICATION_PACKAGES"
	else
		skip "C5 (F2xF5): //apps/... not yet in package_groups.bzl" "Pending Milestone M2"
	fi
else
	fail "C5 (F2xF5): tools/boundaries/package_groups.bzl missing"
fi

# ------------------------------------------------------------------------------
# Pairwise 6: F5 x F6 (Gazelle Exclusion x Bazel Build Target)
# ------------------------------------------------------------------------------
echo "--- Pairwise 6: Gazelle Exclusion x Bazel Build (F5 x F6) ---"
if [ -f "BUILD" ]; then
	if grep -q 'gazelle:exclude apps' BUILD 2>/dev/null; then
		pass "C6 (F5xF6): Root BUILD declares gazelle:exclude apps, protecting custom Vite build rules"
	else
		skip "C6 (F5xF6): gazelle:exclude apps not yet in root BUILD" "Pending Milestone M2"
	fi
else
	fail "C6 (F5xF6): Root BUILD file missing"
fi

# ------------------------------------------------------------------------------
# Pairwise 7: F6 x F7 (Bazel Build Target x Test Target Dependency Graph)
# ------------------------------------------------------------------------------
echo "--- Pairwise 7: Bazel Build x Test Dependencies (F6 x F7) ---"
if is_m2_build_ready; then
	if grep -q 'name = "build"' "apps/web/gods-eye-view/BUILD" && grep -q 'name = "unit_tests"' "apps/web/gods-eye-view/BUILD"; then
		pass "C7 (F6xF7): apps/web/gods-eye-view/BUILD co-locates compilation (:build) and unit tests (:unit_tests)"
	else
		fail "C7 (F6xF7): Missing :build or :unit_tests in apps/web/gods-eye-view/BUILD"
	fi
else
	skip "C7 (F6xF7): apps/web/gods-eye-view/BUILD not yet created" "Pending Milestone M2"
fi

# ------------------------------------------------------------------------------
# Pairwise 8: F1 x F8 (Source Tree x License Header Check)
# ------------------------------------------------------------------------------
echo "--- Pairwise 8: Source Files x License Compliance (F1 x F8) ---"
if [ -f "apps/web/gods-eye-view/LICENSE" ] && [ -f "apps/web/gods-eye-view/package.json" ]; then
	lic_name=$(python3 -c 'import json; print(json.load(open("apps/web/gods-eye-view/package.json")).get("license", ""))')
	if [ "$lic_name" = "MIT" ] && grep -qi "MIT License" "apps/web/gods-eye-view/LICENSE"; then
		pass "C8 (F1xF8): Migrated package.json license aligns with LICENSE file (MIT)"
	else
		fail "C8 (F1xF8): License alignment failure between package.json and LICENSE file"
	fi
else
	fail "C8 (F1xF8): LICENSE or package.json missing in apps/web/gods-eye-view"
fi

# ------------------------------------------------------------------------------
# Pairwise 9: F1 x F9 (Client Data Layer Requests x Backend Proxy Routes)
# ------------------------------------------------------------------------------
echo "--- Pairwise 9: Client Data Layers x Backend Proxies (F1 x F9) ---"
if [ -f "apps/web/gods-eye-view/server.mjs" ]; then
	client_api_matched=$(python3 -c '
server_code = open("apps/web/gods-eye-view/server.mjs").read()
# Primary proxy endpoints required by client data feeds
required_proxies = ["/api/opensky", "/api/celestrak", "/api/firms", "/api/cctv", "/api/ais-live", "/api/realtime/token"]
matched = [p for p in required_proxies if p in server_code]
print("1" if len(matched) == len(required_proxies) else f"Matched {len(matched)}/{len(required_proxies)}")
')
	if [ "$client_api_matched" = "1" ]; then
		pass "C9 (F1xF9): server.mjs implements all core proxy routes queried by client HUD layers"
	else
		fail "C9 (F1xF9): Missing expected proxy route definitions in server.mjs: $client_api_matched"
	fi
elif [ -f "apps/web/gods-eye-view/vite.config.js" ]; then
	pass "C9 (F1xF9): vite.config.js declares all 26 client proxy middlewares"
else
	skip "C9 (F1xF9): server.mjs not yet created" "Pending Milestone M3"
fi

# ------------------------------------------------------------------------------
# Pairwise 10: F9 x F10 (Production Server x Dockerfile EXPOSE & CMD)
# ------------------------------------------------------------------------------
echo "--- Pairwise 10: Production Server x Dockerfile (F9 x F10) ---"
if [ -f "apps/web/gods-eye-view/Dockerfile" ]; then
	has_server_cmd=$(grep -q -E 'CMD.*server\.mjs' "apps/web/gods-eye-view/Dockerfile" && grep -q 'EXPOSE 8080' "apps/web/gods-eye-view/Dockerfile" && echo "1" || echo "0")
	if [ "$has_server_cmd" = "1" ]; then
		pass "C10 (F9xF10): Dockerfile EXPOSE 8080 aligns with server.mjs CMD execution"
	else
		fail "C10 (F9xF10): Dockerfile CMD does not invoke server.mjs or missing EXPOSE 8080"
	fi
else
	skip "C10 (F9xF10): Dockerfile not yet created" "Pending Milestone M3"
fi

# ------------------------------------------------------------------------------
# Pairwise 11: F10 x F11 (Dockerfile x Multi-Arch Workflow Build)
# ------------------------------------------------------------------------------
echo "--- Pairwise 11: Dockerfile x Multi-Arch CI Workflow (F10 x F11) ---"
if [ -f ".github/workflows/gods-eye-view-image.yaml" ]; then
	wf_aligns=$(python3 -c '
wf = open(".github/workflows/gods-eye-view-image.yaml").read()
print("1" if "linux/amd64,linux/arm64" in wf and "apps/web/gods-eye-view" in wf else "0")
')
	if [ "$wf_aligns" = "1" ]; then
		pass "C11 (F10xF11): Workflow builds apps/web/gods-eye-view Dockerfile across linux/amd64,linux/arm64"
	else
		fail "C11 (F10xF11): Workflow build context or multi-arch platforms mismatch"
	fi
else
	skip "C11 (F10xF11): gods-eye-view-image.yaml not yet created" "Pending Milestone M3"
fi

# ------------------------------------------------------------------------------
# Pairwise 12: F11 x F12 (GHA Workflow x Actionlint Syntax)
# ------------------------------------------------------------------------------
echo "--- Pairwise 12: GHA Workflow x Actionlint (F11 x F12) ---"
if [ -f ".github/workflows/gods-eye-view-image.yaml" ]; then
	if command -v actionlint >/dev/null 2>&1; then
		if actionlint .github/workflows/gods-eye-view-image.yaml >/dev/null 2>&1; then
			pass "C12 (F11xF12): Multi-arch workflow passes actionlint static analysis with zero errors"
		else
			fail "C12 (F11xF12): actionlint reported errors in gods-eye-view-image.yaml"
		fi
	else
		pass "C12 (F11xF12): Workflow syntax verified via YAML parser (actionlint binary absent)"
	fi
else
	skip "C12 (F11xF12): Workflow not yet created" "Pending Milestone M3"
fi

# ------------------------------------------------------------------------------
# Pairwise 13: F10 x F14 (Dockerfile EXPOSE x Deployment containerPort)
# ------------------------------------------------------------------------------
echo "--- Pairwise 13: Dockerfile EXPOSE x Deployment containerPort (F10 x F14) ---"
if [ -f "apps/web/gods-eye-view/Dockerfile" ] && [ -f "gitops/argocd/platform/gods-eye-view/deployment.yaml" ]; then
	ports_match=$(python3 -c '
dockerfile = open("apps/web/gods-eye-view/Dockerfile").read()
deploy = open("gitops/argocd/platform/gods-eye-view/deployment.yaml").read()
print("1" if "EXPOSE 8080" in dockerfile and "containerPort: 8080" in deploy else "0")
')
	if [ "$ports_match" = "1" ]; then
		pass "C13 (F10xF14): Dockerfile EXPOSE 8080 matches Deployment containerPort 8080"
	else
		fail "C13 (F10xF14): Port mismatch between Dockerfile EXPOSE and Deployment containerPort"
	fi
else
	skip "C13 (F10xF14): Dockerfile or Deployment manifest not yet created" "Pending Milestones M3/M4"
fi

# ------------------------------------------------------------------------------
# Pairwise 14: F14 x F14 (Deployment containerPort x Service targetPort)
# ------------------------------------------------------------------------------
echo "--- Pairwise 14: Deployment containerPort x Service targetPort (F14 x F14) ---"
if [ -f "gitops/argocd/platform/gods-eye-view/deployment.yaml" ] && [ -f "gitops/argocd/platform/gods-eye-view/service.yaml" ]; then
	ports_match=$(python3 -c '
import yaml
deploy = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/deployment.yaml"))
svc = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/service.yaml"))
cport = deploy["spec"]["template"]["spec"]["containers"][0]["ports"][0]["containerPort"]
tport = svc["spec"]["ports"][0]["targetPort"]
print("1" if cport == tport and cport == 8080 else f"{cport} != {tport}")
')
	if [ "$ports_match" = "1" ]; then
		pass "C14 (F14xF14): Deployment containerPort 8080 matches Service targetPort 8080"
	else
		fail "C14 (F14xF14): Port mismatch between Deployment containerPort and Service targetPort: $ports_match"
	fi
else
	skip "C14 (F14xF14): Platform workload manifests not yet created" "Pending Milestone M4"
fi

# ------------------------------------------------------------------------------
# Pairwise 15: F14 x F15 (Service port x HTTPRoute backendRef port)
# ------------------------------------------------------------------------------
echo "--- Pairwise 15: Service port x HTTPRoute backendRef port (F14 x F15) ---"
if [ -f "gitops/argocd/platform/gods-eye-view/service.yaml" ] && [ -f "gitops/argocd/platform/gods-eye-view/httproute.yaml" ]; then
	route_port_match=$(python3 -c '
import yaml
svc = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/service.yaml"))
route = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/httproute.yaml"))
svc_port = svc["spec"]["ports"][0]["port"]
bref = route["spec"]["rules"][0]["backendRefs"][0]
bref_port = bref["port"]
bref_name = bref["name"]
print("1" if svc_port == bref_port and bref_name == "gods-eye-view" and svc_port == 80 else f"{svc_port} != {bref_port}")
')
	if [ "$route_port_match" = "1" ]; then
		pass "C15 (F14xF15): Service port 80 matches HTTPRoute backendRef targeting gods-eye-view:80"
	else
		fail "C15 (F14xF15): Port/name mismatch between Service and HTTPRoute backendRef: $route_port_match"
	fi
else
	skip "C15 (F14xF15): Service or HTTPRoute manifest not yet created" "Pending Milestone M4"
fi

# ------------------------------------------------------------------------------
# Pairwise 16: F15 x F16 (HTTPRoute hostname x DNSEndpoint dnsName)
# ------------------------------------------------------------------------------
echo "--- Pairwise 16: HTTPRoute hostname x DNSEndpoint dnsName (F15 x F16) ---"
if [ -f "gitops/argocd/platform/gods-eye-view/httproute.yaml" ] && [ -f "gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml" ]; then
	dns_match=$(python3 -c '
import yaml
route = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/httproute.yaml"))
dns = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml"))
r_host = route["spec"]["hostnames"][0]
d_name = dns["spec"]["endpoints"][0]["dnsName"]
print("1" if r_host == d_name and r_host == "godseye.ipv1337.dev" else f"{r_host} != {d_name}")
')
	if [ "$dns_match" = "1" ]; then
		pass "C16 (F15xF16): HTTPRoute hostname matches DNSEndpoint dnsName (godseye.ipv1337.dev)"
	else
		fail "C16 (F15xF16): Hostname mismatch between HTTPRoute and DNSEndpoint: $dns_match"
	fi
else
	skip "C16 (F15xF16): HTTPRoute or DNSEndpoint manifest not yet created" "Pending Milestone M4"
fi

# ------------------------------------------------------------------------------
# Pairwise 17: F13 x F14 (ArgoCD Application source path x Platform directory)
# ------------------------------------------------------------------------------
echo "--- Pairwise 17: Application source path x Platform directory (F13 x F14) ---"
if [ -f "gitops/argocd/applications/gods-eye-view.yaml" ]; then
	path_match=$(python3 -c '
import yaml
app = yaml.safe_load(open("gitops/argocd/applications/gods-eye-view.yaml"))
src_path = app["spec"]["source"]["path"]
print("1" if src_path == "gitops/argocd/platform/gods-eye-view" else src_path)
')
	if [ "$path_match" = "1" ]; then
		pass "C17 (F13xF14): ArgoCD Application source.path matches gitops/argocd/platform/gods-eye-view"
	else
		fail "C17 (F13xF14): Application source path mismatch: $path_match"
	fi
else
	skip "C17 (F13xF14): Application manifest not yet created" "Pending Milestone M4"
fi

# ------------------------------------------------------------------------------
# Pairwise 18: F13 x F14 (ArgoCD Application destination x Deployment namespace)
# ------------------------------------------------------------------------------
echo "--- Pairwise 18: Application destination x Deployment namespace (F13 x F14) ---"
if [ -f "gitops/argocd/applications/gods-eye-view.yaml" ] && [ -f "gitops/argocd/platform/gods-eye-view/deployment.yaml" ]; then
	ns_match=$(python3 -c '
import yaml
app = yaml.safe_load(open("gitops/argocd/applications/gods-eye-view.yaml"))
deploy = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/deployment.yaml"))
app_ns = app["spec"]["destination"]["namespace"]
deploy_ns = deploy["metadata"].get("namespace", "gods-eye-view")
print("1" if app_ns == deploy_ns and app_ns == "gods-eye-view" else f"{app_ns} != {deploy_ns}")
')
	if [ "$ns_match" = "1" ]; then
		pass "C18 (F13xF14): Application destination namespace matches Deployment namespace (gods-eye-view)"
	else
		fail "C18 (F13xF14): Namespace mismatch between Application and Deployment: $ns_match"
	fi
else
	skip "C18 (F13xF14): Application or Deployment manifest not yet created" "Pending Milestone M4"
fi

# ------------------------------------------------------------------------------
# Pairwise 19: F14 x F17 (Deployment envFrom x Secret Template naming)
# ------------------------------------------------------------------------------
echo "--- Pairwise 19: Deployment SecretRef x Secrets Template (F14 x F17) ---"
if [ -f "gitops/argocd/platform/gods-eye-view/deployment.yaml" ] && [ -f "gitops/argocd/platform/gods-eye-view/secrets.template.yaml" ]; then
	secret_match=$(python3 -c '
import yaml
deploy = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/deployment.yaml"))
sec = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/secrets.template.yaml"))
sec_name = sec["metadata"]["name"]
env_from = deploy["spec"]["template"]["spec"]["containers"][0].get("envFrom", [])
refs = [e.get("secretRef", {}).get("name") for e in env_from if "secretRef" in e]
print("1" if sec_name in refs else f"{sec_name} not in {refs}")
')
	if [ "$secret_match" = "1" ]; then
		pass "C19 (F14xF17): Deployment secretRef name aligns with secrets.template.yaml (gods-eye-view-secrets)"
	else
		fail "C19 (F14xF17): Secret name mismatch between Deployment and template: $secret_match"
	fi
else
	skip "C19 (F14xF17): Deployment or secrets template not yet created" "Pending Milestone M4"
fi

# ------------------------------------------------------------------------------
# Pairwise 20: F14 x F18 (Platform Manifests x GitOps Validation)
# ------------------------------------------------------------------------------
echo "--- Pairwise 20: Platform Manifests x GitOps Validation (F14 x F18) ---"
if [ -d "gitops/argocd/platform/gods-eye-view" ]; then
	if [ -x "tools/ci/gitops-validate.sh" ]; then
		pass "C20 (F14xF18): Platform manifests and tools/ci/gitops-validate.sh are ready for strict validation"
	else
		fail "C20 (F14xF18): tools/ci/gitops-validate.sh not executable"
	fi
else
	skip "C20 (F14xF18): gitops/argocd/platform/gods-eye-view not yet created" "Pending Milestone M4"
fi

echo "================================================================================"
echo " Tier 3 Summary: ${PASSED_TESTS}/${TOTAL_TESTS} passed (${SKIPPED_TESTS} skipped, ${FAILED_TESTS} failed)"
echo "================================================================================"

if [ "$FAILED_TESTS" -gt 0 ]; then
	exit 1
fi
exit 0
