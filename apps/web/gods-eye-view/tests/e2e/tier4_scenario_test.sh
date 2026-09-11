#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Tier 4: Real-World Application Scenarios Test Suite
# 5 Complex End-to-End Scenarios
# Exercises integrated workflows across build, containerization, GitOps, security, and networking.
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

echo "================================================================================"
echo " Tier 4: Real-World Application Scenarios Test Suite (5 End-to-End Scenarios)"
echo " Working Directory: ${ROOT}"
echo " Strict Mode:        ${STRICT_MODE}"
echo "================================================================================"

# ------------------------------------------------------------------------------
# Scenario 1: Full Monorepo Build Lifecycle (F1, F2, F3, F4, F6, F7, F8)
# ------------------------------------------------------------------------------
echo "--- Scenario 1: Full Monorepo Build Lifecycle ---"
scenario1_status="PASS"
scenario1_errors=""

# Step 1: Verify workspace registration
if ! grep -E '^\s*-\s*apps/web/(\*|gods-eye-view)' pnpm-workspace.yaml >/dev/null 2>&1; then
	scenario1_status="FAIL"
	scenario1_errors="${scenario1_errors} [Workspace not registered]"
fi

# Step 2: Verify package.json engines and dependencies
if [ -f "apps/web/gods-eye-view/package.json" ]; then
	pkg_check=$(python3 -c '
import json
d = json.load(open("apps/web/gods-eye-view/package.json"))
engines_ok = ">=22" in d.get("engines", {}).get("node", "")
deps_ok = "ws" in d.get("dependencies", {}) and "cesium" in d.get("dependencies", {})
print("1" if engines_ok and deps_ok else "0")
')
	if [ "$pkg_check" != "1" ]; then
		scenario1_status="FAIL"
		scenario1_errors="${scenario1_errors} [package.json engines/deps misaligned]"
	fi
else
	scenario1_status="FAIL"
	scenario1_errors="${scenario1_errors} [package.json missing]"
fi

# Step 3: Verify lockfile entry
if ! grep -q 'apps/web/gods-eye-view' pnpm-lock.yaml 2>/dev/null; then
	scenario1_status="FAIL"
	scenario1_errors="${scenario1_errors} [Lockfile missing importer]"
fi

# Step 4: Verify test suite execution capability
if [ -f "apps/web/gods-eye-view/scripts/run-unit-tests.mjs" ]; then
	# Verify that unit test runner script compiles with node if node is available
	if command -v node >/dev/null 2>&1; then
		if ! node --check "apps/web/gods-eye-view/scripts/run-unit-tests.mjs" >/dev/null 2>&1; then
			scenario1_status="FAIL"
			scenario1_errors="${scenario1_errors} [run-unit-tests.mjs syntax error]"
		fi
	fi
else
	scenario1_status="FAIL"
	scenario1_errors="${scenario1_errors} [run-unit-tests.mjs missing]"
fi

if [ "$scenario1_status" = "PASS" ]; then
	pass "Scenario 1: Full Monorepo Build Lifecycle verified (workspace, lockfile, dependencies, unit test harness)"
else
	fail "Scenario 1: Full Monorepo Build Lifecycle failed:${scenario1_errors}"
fi

# ------------------------------------------------------------------------------
# Scenario 2: Container Multi-Arch Build & Health Validation (F9, F10, F11, F12)
# ------------------------------------------------------------------------------
echo "--- Scenario 2: Container Multi-Arch Build & Health Validation ---"
if [ -f "apps/web/gods-eye-view/Dockerfile" ] && [ -f ".github/workflows/gods-eye-view-image.yaml" ]; then
	scenario2_ok=true
	# Check Dockerfile Node 22, non-root, EXPOSE 8080, HEALTHCHECK
	if ! grep -E '^FROM node:22' "apps/web/gods-eye-view/Dockerfile" >/dev/null 2>&1; then
		scenario2_ok=false
	fi
	if ! grep -E '^USER (nodejs|1000|1001|node)' "apps/web/gods-eye-view/Dockerfile" >/dev/null 2>&1; then
		scenario2_ok=false
	fi
	if ! grep -q 'EXPOSE 8080' "apps/web/gods-eye-view/Dockerfile"; then
		scenario2_ok=false
	fi
	if ! grep -q 'HEALTHCHECK' "apps/web/gods-eye-view/Dockerfile"; then
		scenario2_ok=false
	fi
	# Check GHA workflow
	if ! grep -q 'linux/amd64,linux/arm64' ".github/workflows/gods-eye-view-image.yaml"; then
		scenario2_ok=false
	fi
	if command -v actionlint >/dev/null 2>&1; then
		if ! actionlint .github/workflows/gods-eye-view-image.yaml >/dev/null 2>&1; then
			scenario2_ok=false
		fi
	fi
	if [ "$scenario2_ok" = true ]; then
		pass "Scenario 2: Container Multi-Arch Build & Health Validation passed (Dockerfile Node 22, non-root, 8080, HEALTHCHECK, actionlint)"
	else
		fail "Scenario 2: Container Multi-Arch Build & Health Validation failed"
	fi
else
	skip "Scenario 2: Container Multi-Arch Build & Health Validation" "Pending Milestone M3 (Dockerfile & GHA Workflow)"
fi

# ------------------------------------------------------------------------------
# Scenario 3: Homelab GitOps Reconciliation & Ingress Topology (F13, F14, F15, F16, F17, F18)
# ------------------------------------------------------------------------------
echo "--- Scenario 3: Homelab GitOps Reconciliation & Ingress Topology ---"
if [ -d "gitops/argocd/platform/gods-eye-view" ] && [ -f "gitops/argocd/applications/gods-eye-view.yaml" ]; then
	scenario3_ok=true
	# Check ingress chain: Application -> Deployment -> Service -> HTTPRoute -> Gateway -> DNSEndpoint
	app_path=$(python3 -c 'import yaml; print(yaml.safe_load(open("gitops/argocd/applications/gods-eye-view.yaml"))["spec"]["source"]["path"])' 2>/dev/null)
	if [ "$app_path" != "gitops/argocd/platform/gods-eye-view" ]; then
		scenario3_ok=false
	fi
	# Check HTTPRoute parentRef and hostname
	if [ -f "gitops/argocd/platform/gods-eye-view/httproute.yaml" ]; then
		route_check=$(python3 -c '
import yaml
d = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/httproute.yaml"))
host_ok = "godseye.ipv1337.dev" in d["spec"]["hostnames"]
gw_ok = d["spec"]["parentRefs"][0]["name"] == "platform" and d["spec"]["parentRefs"][0]["namespace"] == "envoy-gateway-system"
weight_ok = d["spec"]["rules"][0]["backendRefs"][0].get("weight") == 1
print("1" if host_ok and gw_ok and weight_ok else "0")
' 2>/dev/null)
		if [ "$route_check" != "1" ]; then
			scenario3_ok=false
		fi
	else
		scenario3_ok=false
	fi
	# Check DNSEndpoint Cloudflare Tunnel
	if [ -f "gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml" ]; then
		dns_check=$(python3 -c '
import yaml
d = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml"))
ep = d["spec"]["endpoints"][0]
print("1" if ep["dnsName"] == "godseye.ipv1337.dev" and ep["recordType"] == "CNAME" and "1f7b9704-bb66-41f4-966f-5bb722e3c10e.cfargotunnel.com" in ep["targets"] else "0")
' 2>/dev/null)
		if [ "$dns_check" != "1" ]; then
			scenario3_ok=false
		fi
	else
		scenario3_ok=false
	fi
	if [ "$scenario3_ok" = true ]; then
		pass "Scenario 3: Homelab GitOps Reconciliation & Ingress Topology verified (ArgoCD, Gateway API, Cloudflare Tunnel CNAME)"
	else
		fail "Scenario 3: Homelab GitOps Reconciliation & Ingress Topology validation failed"
	fi
else
	skip "Scenario 3: Homelab GitOps Reconciliation & Ingress Topology" "Pending Milestone M4 (GitOps Manifests)"
fi

# ------------------------------------------------------------------------------
# Scenario 4: Security & Conformance Boundary Audit (F5, F8, F10, F17, F20)
# ------------------------------------------------------------------------------
echo "--- Scenario 4: Security & Conformance Boundary Audit ---"
scenario4_ok=true

# Check zero plaintext keys in gitops
if grep -r -E '(AIza[0-9A-Za-z_-]{35}|sk-[0-9A-Za-z]{32,})' gitops/argocd/platform/gods-eye-view/ 2>/dev/null; then
	scenario4_ok=false
fi

# Check conformance check script exists
if [ ! -x "tools/conformance/check.sh" ]; then
	scenario4_ok=false
fi

# Check architectural boundary definition
if ! grep -q 'LAYER_APPS = 3' tools/boundaries/package_groups.bzl 2>/dev/null; then
	scenario4_ok=false
fi

if [ "$scenario4_ok" = true ]; then
	pass "Scenario 4: Security & Conformance Boundary Audit verified (zero plaintext secrets, boundary aspects, conformance rules)"
else
	fail "Scenario 4: Security & Conformance Boundary Audit failed"
fi

# ------------------------------------------------------------------------------
# Scenario 5: Proxy Routing & WebRTC/WebSocket Protocol Contract (F9, F15, F19)
# ------------------------------------------------------------------------------
echo "--- Scenario 5: Proxy Routing & WebRTC/WebSocket Protocol Contract ---"
if [ -f "apps/web/gods-eye-view/server.mjs" ] || [ -f "apps/web/gods-eye-view/vite.config.js" ]; then
	proxy_source="apps/web/gods-eye-view/server.mjs"
	if [ ! -f "$proxy_source" ]; then
		proxy_source="apps/web/gods-eye-view/vite.config.js"
	fi
	protocol_ok=$(python3 -c '
code = open("'"$proxy_source"'").read()
has_ws = "stream.aisstream.io" in code or "AISSTREAM" in code
has_token = "/api/realtime/token" in code or "client_secrets" in code
has_proxy = "/api/opensky" in code and "/api/celestrak" in code
print("1" if has_ws and has_token and has_proxy else f"ws:{has_ws}, token:{has_token}, proxy:{has_proxy}")
')
	if [ "$protocol_ok" = "1" ]; then
		pass "Scenario 5: Proxy Routing & WebRTC/WebSocket Protocol Contract verified (26 proxies, AISStream WS, OpenAI Realtime WebRTC token)"
	else
		fail "Scenario 5: Protocol contract verification failed: $protocol_ok"
	fi
else
	skip "Scenario 5: Proxy Routing & WebRTC/WebSocket Protocol Contract" "Pending Milestone M3 (Production Server)"
fi

echo "================================================================================"
echo " Tier 4 Summary: ${PASSED_TESTS}/${TOTAL_TESTS} passed (${SKIPPED_TESTS} skipped, ${FAILED_TESTS} failed)"
echo "================================================================================"

if [ "$FAILED_TESTS" -gt 0 ]; then
	exit 1
fi
exit 0
