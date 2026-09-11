#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
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

info() {
	echo "    # Info: $1"
}

echo "================================================================================"
echo " Tier 5: Adversarial Coverage Hardening Test Suite (37 Tests)"
echo " Working Directory: ${ROOT}"
echo " Strict Mode:       ${STRICT_MODE}"
echo "================================================================================"

# ==============================================================================
# Category A: Live Server Routing, SSRF Defenses & WebSocket Resilience (Challenger 1)
# ==============================================================================
SERVER_PORT=8199
BASE_URL="http://127.0.0.1:$SERVER_PORT"
WS_URL="ws://127.0.0.1:$SERVER_PORT"
SERVER_PID=""

cleanup_server() {
	if [ -n "$SERVER_PID" ]; then
		kill -9 "$SERVER_PID" 2>/dev/null || true
		wait "$SERVER_PID" 2>/dev/null || true
	fi
}
trap cleanup_server EXIT INT TERM

# Start test server on ephemeral port with restrictive rate limit for testing
PORT="$SERVER_PORT" AUTO_START_SERVER=true GEV_RATELIMIT_OPENAI_PER_MIN=3 node "$ROOT/apps/web/gods-eye-view/server.mjs" >/dev/null 2>&1 &
SERVER_PID=$!

# Wait for server readiness
for _ in {1..30}; do
	if curl -s "$BASE_URL/healthz" >/dev/null 2>&1; then
		break
	fi
	sleep 0.1
done

echo "--- Category A: Server Routes, Proxies, SSRF Defenses & WebSockets ---"

# ADV-01: CelesTrak Subpath Routing (/api/celestrak/stations)
test_tier5_adv_01_celestrak_subpath_routing() {
	local code body
	code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/celestrak/stations")
	body=$(curl -s "$BASE_URL/api/celestrak/stations")
	if [ "$code" = "200" ]; then
		pass "ADV-01: /api/celestrak/stations routes correctly (upstream 200 OK)"
	elif [ "$code" = "403" ] && echo "$body" | grep -qi "celestrak"; then
		pass "ADV-01: /api/celestrak/stations routes correctly to upstream celestrak.org (upstream 403 rate-limited)"
	else
		fail "ADV-01: /api/celestrak/stations failed (got $code, expected 200 or upstream celestrak response)"
	fi
}

# ADV-02: Radio Subpath Routing (/api/radio/stations)
test_tier5_adv_02_radio_subpath_routing() {
	local code body
	code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/radio/stations")
	body=$(curl -s "$BASE_URL/api/radio/stations")
	if [ "$code" = "200" ]; then
		pass "ADV-02: /api/radio/stations routes correctly (upstream 200 OK)"
	elif [ "$code" = "429" ] || [ "$code" = "503" ]; then
		pass "ADV-02: /api/radio/stations routes correctly to upstream radio-browser (upstream $code rate-limited/degraded)"
	elif [ "$code" = "502" ] || [ "$code" = "504" ]; then
		pass "ADV-02: /api/radio/stations routes correctly to upstream radio-browser (upstream $code gateway error)"
	else
		fail "ADV-02: /api/radio/stations failed with HTTP $code"
	fi
}

# ADV-03: SSRF IPv4-Mapped IPv6 Loopback Rejection
test_tier5_adv_03_ssrf_ipv4_mapped_ipv6() {
	local code
	code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/cctv/frame?url=http://%5B::ffff:127.0.0.1%5D/admin")
	if [ "$code" = "403" ]; then
		pass "ADV-03: SSRF IPv4-mapped IPv6 loopback blocked with 403 Forbidden"
	else
		fail "ADV-03: SSRF IPv4-mapped IPv6 loopback not blocked with 403 (got $code)"
	fi
}

# ADV-04: SSRF DNS Rebinding Defense (nip.io)
test_tier5_adv_04_ssrf_dns_rebinding() {
	local code
	code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/cctv/frame?url=http://127.0.0.1.nip.io/admin")
	if [ "$code" = "403" ]; then
		pass "ADV-04: SSRF DNS rebinding to loopback blocked with 403"
	else
		fail "ADV-04: SSRF DNS rebinding not blocked with 403 (got $code)"
	fi
}

# ADV-05: SSRF Cloud Metadata Endpoint Blocking
test_tier5_adv_05_ssrf_internal_cloud_metadata() {
	local code
	code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/cctv/frame?url=http://metadata.google.internal/computeMetadata/v1/")
	if [ "$code" = "403" ]; then
		pass "ADV-05: SSRF cloud metadata endpoint blocked with 403"
	else
		fail "ADV-05: SSRF cloud metadata not blocked with 403 (got $code)"
	fi
}

# ADV-06: Protocol Smuggling Prevention (file:// scheme)
test_tier5_adv_06_ssrf_protocol_smuggling() {
	local code
	code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/cctv/frame?url=file:///etc/passwd")
	if [ "$code" = "400" ]; then
		pass "ADV-06: Non-HTTP protocol file:// rejected with 400 Bad Request"
	else
		fail "ADV-06: Non-HTTP protocol file:// not rejected with 400 (got $code)"
	fi
}

# ADV-07: Setup Keys Disallowed Key Injection
test_tier5_adv_07_setup_keys_disallowed_injection() {
	local code
	code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d '{"LD_PRELOAD":"/tmp/evil.so"}' "$BASE_URL/api/setup/keys")
	if [ "$code" = "400" ]; then
		pass "ADV-07: Disallowed environment key injection rejected with 400"
	else
		fail "ADV-07: Disallowed key injection not rejected with 400 (got $code)"
	fi
}

# ADV-08: Setup Keys Malformed JSON Rejection
test_tier5_adv_08_setup_keys_malformed_json() {
	local code
	code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d '{"broken-json' "$BASE_URL/api/setup/keys")
	if [ "$code" = "400" ]; then
		pass "ADV-08: Malformed JSON rejected with 400 Bad Request"
	else
		fail "ADV-08: Malformed JSON not rejected with 400 (got $code)"
	fi
}

# ADV-09: Setup Keys Oversized Payload Rejection
test_tier5_adv_09_setup_keys_payload_too_large() {
	local code
	code=$(node -e '
		const http = require("http");
		const req = http.request("'"$BASE_URL"'/api/setup/keys", {
			method: "POST",
			headers: { "Content-Type": "application/json" }
		}, (res) => {
			console.log(res.statusCode);
			process.exit(0);
		});
		req.on("error", () => {
			process.exit(0);
		});
		req.write("{\"OPENAI_API_KEY\":\"" + "x".repeat(2 * 1024 * 1024) + "\"}");
		req.end();
	')
	if [ "$code" = "413" ]; then
		pass "ADV-09: Oversized setup payload (>1MB) rejected with 413 Payload Too Large"
	else
		fail "ADV-09: Oversized payload not rejected with 413 (got $code)"
	fi
}

# ADV-10: Rate Limiting Enforcement on Token Minting
test_tier5_adv_10_ratelimit_enforcement_openai() {
	local c1 c2 c3 c4
	c1=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/realtime/token")
	c2=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/realtime/token")
	c3=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/realtime/token")
	c4=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/realtime/token")
	if [ "$c4" = "429" ]; then
		pass "ADV-10: Rate limiter triggers HTTP 429 upon exceeding window limit"
	else
		fail "ADV-10: Rate limiter failed to throttle 4th request (got $c4)"
	fi
}

# ADV-11: Rate Limiter Identity Trust & Header Verification
test_tier5_adv_11_ratelimit_header_spoofing_bypass() {
	local c1 c2
	curl -s -H "X-Forwarded-For: 10.99.1.1" "$BASE_URL/api/realtime/token" >/dev/null
	curl -s -H "X-Forwarded-For: 10.99.1.1" "$BASE_URL/api/realtime/token" >/dev/null
	curl -s -H "X-Forwarded-For: 10.99.1.1" "$BASE_URL/api/realtime/token" >/dev/null
	c1=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Forwarded-For: 10.99.1.1" "$BASE_URL/api/realtime/token")
	c2=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Forwarded-For: 10.99.1.2" "$BASE_URL/api/realtime/token")
	if [ "$c1" = "429" ] && [ "$c2" = "429" ]; then
		pass "ADV-11: Rate limiter immune to X-Forwarded-For IP spoofing"
	else
		fail "ADV-11: Rate limiter bypassed via rotated X-Forwarded-For header ($c1 vs $c2)"
	fi
}

# ADV-12: WebSocket Binary Frame Injection Resilience
test_tier5_adv_12_websocket_binary_frame_injection() {
	local res
	res=$(node --input-type=module -e '
		let WebSocket;
		try {
			const pkg = await import("./apps/web/gods-eye-view/node_modules/ws/index.js");
			WebSocket = pkg.default?.WebSocket || pkg.WebSocket || pkg.default;
		} catch {
			const pkg = await import("ws");
			WebSocket = pkg.default?.WebSocket || pkg.WebSocket || pkg.default;
		}
		const ws = new WebSocket("'"$WS_URL"'");
		ws.on("open", () => {
			ws.send(Buffer.alloc(65536, 0x5a));
			setTimeout(() => { ws.close(); console.log("SURVIVED"); process.exit(0); }, 200);
		});
		ws.on("error", (e) => { console.log("ERROR:" + e.message); process.exit(1); });
	')
	if [ "$res" = "SURVIVED" ]; then
		pass "ADV-12: Inbound WebSocket survived 64KB binary frame injection"
	else
		fail "ADV-12: WebSocket crashed or errored on binary injection ($res)"
	fi
}

# ADV-13: WebSocket High Connection Churn & Socket Reset Resilience
test_tier5_adv_13_websocket_high_connection_churn() {
	local res
	res=$(node --input-type=module -e '
		let WebSocket;
		try {
			const pkg = await import("./apps/web/gods-eye-view/node_modules/ws/index.js");
			WebSocket = pkg.default?.WebSocket || pkg.WebSocket || pkg.default;
		} catch {
			const pkg = await import("ws");
			WebSocket = pkg.default?.WebSocket || pkg.WebSocket || pkg.default;
		}
		let closed = 0;
		for (let i = 0; i < 30; i++) {
			const ws = new WebSocket("'"$WS_URL"'");
			ws.on("open", () => {
				if (i % 2 === 0) ws._socket.destroy();
				else ws.close();
			});
			ws.on("error", () => {});
			ws.on("close", () => {
				closed++;
				if (closed === 30) { console.log("CHURN_SUCCESS"); process.exit(0); }
			});
		}
	')
	if [ "$res" = "CHURN_SUCCESS" ]; then
		pass "ADV-13: WebSocket server withstood 30 rapid connections with abrupt socket resets"
	else
		fail "ADV-13: WebSocket churn failed ($res)"
	fi
}

# ADV-14: WebSocket Initial Snapshot Message Delivery
test_tier5_adv_14_websocket_initial_snapshot() {
	local res
	res=$(node --input-type=module -e '
		let WebSocket;
		try {
			const pkg = await import("./apps/web/gods-eye-view/node_modules/ws/index.js");
			WebSocket = pkg.default?.WebSocket || pkg.WebSocket || pkg.default;
		} catch {
			const pkg = await import("ws");
			WebSocket = pkg.default?.WebSocket || pkg.WebSocket || pkg.default;
		}
		const ws = new WebSocket("'"$WS_URL"'");
		ws.on("message", (data) => {
			const parsed = JSON.parse(data.toString());
			if (parsed.type === "snapshot" && Array.isArray(parsed.rows)) {
				console.log("SNAPSHOT_VALID");
			}
			ws.close();
			process.exit(0);
		});
		ws.on("error", () => process.exit(1));
	')
	if [ "$res" = "SNAPSHOT_VALID" ]; then
		pass "ADV-14: Inbound WebSocket delivers initial snapshot message upon connection"
	else
		fail "ADV-14: Failed to receive initial snapshot envelope ($res)"
	fi
}

# ADV-15: CCTV Graceful Fallback SVG Response
test_tier5_adv_15_cctv_svg_fallback() {
	local ct
	ct=$(curl -s -I "$BASE_URL/api/cctv" | grep -i "content-type:" | tr -d '\r')
	if [[ "$ct" == *"image/svg+xml"* ]]; then
		pass "ADV-15: CCTV endpoint serves fallback SVG when no url parameter provided"
	else
		fail "ADV-15: Expected image/svg+xml for CCTV fallback, got $ct"
	fi
}

# ADV-16: GBFS Encoded SSRF Target Rejection
test_tier5_adv_16_gbfs_encoded_url_ssrf() {
	local code
	code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/gbfs/http%3A%2F%2F127.0.0.1%3A8080%2Fapi")
	if [ "$code" = "403" ]; then
		pass "ADV-16: Encoded SSRF target in /api/gbfs/<url> blocked with 403 Forbidden"
	else
		fail "ADV-16: Encoded SSRF target in /api/gbfs/<url> not blocked with 403 (got $code)"
	fi
}

# ADV-17: AIS Live Track Query Parameter Validation
test_tier5_adv_17_ais_live_track_missing_mmsi() {
	local code
	code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/ais-live/track")
	if [ "$code" = "400" ]; then
		pass "ADV-17: /api/ais-live/track without mmsi rejected with 400 Bad Request"
	else
		fail "ADV-17: /api/ais-live/track missing mmsi did not return 400 (got $code)"
	fi
}

# ADV-18: Regional Brief Coordinates Out-of-Bounds Resilience
test_tier5_adv_18_regional_brief_weather_resilience() {
	local code
	code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/regional-brief?latitude=9999&longitude=9999")
	if [ "$code" = "200" ]; then
		pass "ADV-18: /api/regional-brief degrades gracefully on out-of-bounds coordinates"
	else
		fail "ADV-18: /api/regional-brief failed with HTTP $code on invalid coordinates"
	fi
}

# ADV-19: Static Asset Serving Directory Traversal Resistance
test_tier5_adv_19_static_file_path_traversal() {
	local code
	code=$(curl -s -o /dev/null -w "%{http_code}" --path-as-is "$BASE_URL/../../../../etc/passwd.txt")
	if [ "$code" = "403" ] || [ "$code" = "404" ]; then
		pass "ADV-19: Path traversal escape outside dist/ prevented (HTTP $code)"
	else
		fail "ADV-19: Path traversal escape outside dist/ not blocked (got $code)"
	fi
}

# ADV-20: Health and Diagnostic Telemetry Readiness
test_tier5_adv_20_healthz_and_ping_endpoints() {
	local code status
	code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/healthz")
	status=$(curl -s "$BASE_URL/healthz" | grep -o '"status":"[^"]*"' | head -n1 || echo "")
	if [ "$code" = "200" ] && [ "$status" = '"status":"ok"' ]; then
		pass "ADV-20: /healthz returns 200 with healthy telemetry payload"
	else
		fail "ADV-20: /healthz telemetry failed (HTTP $code, status: $status)"
	fi
}

test_tier5_adv_01_celestrak_subpath_routing
test_tier5_adv_02_radio_subpath_routing
test_tier5_adv_03_ssrf_ipv4_mapped_ipv6
test_tier5_adv_04_ssrf_dns_rebinding
test_tier5_adv_05_ssrf_internal_cloud_metadata
test_tier5_adv_06_ssrf_protocol_smuggling
test_tier5_adv_07_setup_keys_disallowed_injection
test_tier5_adv_08_setup_keys_malformed_json
test_tier5_adv_09_setup_keys_payload_too_large
test_tier5_adv_10_ratelimit_enforcement_openai
test_tier5_adv_11_ratelimit_header_spoofing_bypass
test_tier5_adv_12_websocket_binary_frame_injection
test_tier5_adv_13_websocket_high_connection_churn
test_tier5_adv_14_websocket_initial_snapshot
test_tier5_adv_15_cctv_svg_fallback
test_tier5_adv_16_gbfs_encoded_url_ssrf
test_tier5_adv_17_ais_live_track_missing_mmsi
test_tier5_adv_18_regional_brief_weather_resilience
test_tier5_adv_19_static_file_path_traversal
test_tier5_adv_20_healthz_and_ping_endpoints

# Stop background server
cleanup_server
SERVER_PID=""

# ==============================================================================
# Category B: GitOps, Container Security, CI Workflow & Monorepo Integration (Challenger 2)
# ==============================================================================
echo "--- Category B: GitOps, Container Security, CI Workflow & Monorepo ---"

test_tier5_adv_k8s_01_pod_security_restricted() {
	if python3 -c '
import yaml
d = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/deployment.yaml"))
spec = d["spec"]["template"]["spec"]
sec = spec.get("securityContext", {})
c_sec = spec["containers"][0].get("securityContext", {})

assert spec.get("automountServiceAccountToken") is False, "automountServiceAccountToken must be false"
assert sec.get("runAsNonRoot") is True, "runAsNonRoot must be true"
assert sec.get("runAsUser") == 1001, "runAsUser must be 1001"
assert sec.get("runAsGroup") == 1001, "runAsGroup must be 1001"
assert sec.get("fsGroup") == 1001, "fsGroup must be 1001"
assert sec.get("seccompProfile", {}).get("type") == "RuntimeDefault", "seccompProfile must be RuntimeDefault"

assert c_sec.get("allowPrivilegeEscalation") is False, "allowPrivilegeEscalation must be false"
assert c_sec.get("readOnlyRootFilesystem") is True, "readOnlyRootFilesystem must be true"
assert "ALL" in c_sec.get("capabilities", {}).get("drop", []), "capabilities.drop must contain ALL"
assert not spec.get("hostNetwork", False), "hostNetwork forbidden"
assert not spec.get("hostPID", False), "hostPID forbidden"
assert not spec.get("hostIPC", False), "hostIPC forbidden"
' 2>/dev/null; then
		pass "ADV-21 (K8S-01): Pod Security Restricted Profile strictly enforced in deployment.yaml"
	else
		fail "ADV-21 (K8S-01): Pod Security Restricted Profile violation detected in deployment.yaml"
	fi
}

test_tier5_adv_k8s_02_volume_mount_isolation() {
	if python3 -c '
import yaml
d = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/deployment.yaml"))
spec = d["spec"]["template"]["spec"]
vm = spec["containers"][0].get("volumeMounts", [])
v = spec.get("volumes", [])

mount_paths = [m["mountPath"] for m in vm]
assert "/tmp" in mount_paths, "/tmp must be mounted for readOnlyRootFilesystem"

vol_names = {vol["name"]: vol for vol in v}
for m in vm:
    vname = m["name"]
    vol = vol_names.get(vname)
    assert vol is not None, f"Volume {vname} not found in spec.volumes"
    assert "hostPath" not in vol, f"Dangerous hostPath volume detected: {vname}"
    assert "emptyDir" in vol or "secret" in vol or "configMap" in vol, f"Volume {vname} is not safe type"
' 2>/dev/null; then
		pass "ADV-22 (K8S-02): Volume mounts isolated to safe emptyDir, zero hostPath volumes"
	else
		fail "ADV-22 (K8S-02): Volume mount isolation check failed"
	fi
}

test_tier5_adv_k8s_03_probe_threshold_safety() {
	if python3 -c '
import yaml
d = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/deployment.yaml"))
c = d["spec"]["template"]["spec"]["containers"][0]
lp = c.get("livenessProbe", {})
rp = c.get("readinessProbe", {})

assert lp.get("httpGet", {}).get("path") == "/healthz", "livenessProbe path must be /healthz"
assert lp.get("httpGet", {}).get("port") == 8080, "livenessProbe port must be 8080"
assert lp.get("timeoutSeconds", 0) < lp.get("periodSeconds", 0), "liveness timeout must be < period"
assert lp.get("initialDelaySeconds", 0) >= 5, "initialDelaySeconds should be >= 5"

assert rp.get("httpGet", {}).get("path") == "/healthz", "readinessProbe path must be /healthz"
assert rp.get("httpGet", {}).get("port") == 8080, "readinessProbe port must be 8080"
assert rp.get("timeoutSeconds", 0) < rp.get("periodSeconds", 0), "readiness timeout must be < period"
' 2>/dev/null; then
		pass "ADV-23 (K8S-03): Health probes configure safe timeout and interval thresholds on port 8080"
	else
		fail "ADV-23 (K8S-03): Health probe threshold safety check failed"
	fi
}

test_tier5_adv_k8s_04_httproute_gateway_ref_integrity() {
	if python3 -c '
import yaml
d = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/httproute.yaml"))
spec = d["spec"]

assert spec.get("hostnames") == ["godseye.ipv1337.dev"], "hostnames must be [godseye.ipv1337.dev]"
pref = spec["parentRefs"][0]
assert pref.get("group") == "gateway.networking.k8s.io", "parentRef group must be gateway.networking.k8s.io"
assert pref.get("kind") == "Gateway", "parentRef kind must be Gateway"
assert pref.get("name") == "platform", "parentRef name must be platform"
assert pref.get("namespace") == "envoy-gateway-system", "parentRef namespace must be envoy-gateway-system"
' 2>/dev/null; then
		pass "ADV-24 (K8S-04): HTTPRoute parentRefs strictly bound to platform Gateway in envoy-gateway-system"
	else
		fail "ADV-24 (K8S-04): HTTPRoute parentRef integrity check failed"
	fi
}

test_tier5_adv_k8s_05_httproute_backend_service_parity() {
	if python3 -c '
import yaml
hr = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/httproute.yaml"))
svc = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/service.yaml"))
dep = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/deployment.yaml"))

bref = hr["spec"]["rules"][0]["backendRefs"][0]
assert bref["name"] == svc["metadata"]["name"], "backendRef name must match Service metadata.name"
assert bref["port"] == svc["spec"]["ports"][0]["port"], "backendRef port must match Service port"
assert bref.get("weight") == 1, "backendRef weight must be explicit 1 to prevent SSA drift"

container_ports = [p["containerPort"] for p in dep["spec"]["template"]["spec"]["containers"][0]["ports"]]
assert svc["spec"]["ports"][0]["targetPort"] in container_ports, "Service targetPort must match containerPort"
' 2>/dev/null; then
		pass "ADV-25 (K8S-05): HTTPRoute backendRef port and name strictly align with Service and Deployment topology"
	else
		fail "ADV-25 (K8S-05): Ingress backend topology alignment check failed"
	fi
}

test_tier5_adv_k8s_06_dnsendpoint_tunnel_cname_coherence() {
	if python3 -c '
import yaml, re
dns = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml"))
hr = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/httproute.yaml"))

ep = dns["spec"]["endpoints"][0]
assert ep["dnsName"] == hr["spec"]["hostnames"][0], "dnsName must match HTTPRoute hostname"
assert ep["recordType"] == "CNAME", "recordType must be CNAME"
assert ep["recordTTL"] == 1, "recordTTL must be 1 for Cloudflare proxied record"

target = ep["targets"][0]
assert re.match(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.cfargotunnel\.com$", target), f"Invalid Cloudflare Tunnel CNAME target: {target}"

ann = dns["metadata"].get("annotations", {})
assert ann.get("external-dns.alpha.kubernetes.io/cloudflare-proxied") == "true", "annotation cloudflare-proxied must be true"

ps = {p["name"]: p["value"] for p in ep.get("providerSpecific", [])}
assert ps.get("external-dns.alpha.kubernetes.io/cloudflare-proxied") == "true", "providerSpecific cloudflare-proxied must be true"
' 2>/dev/null; then
		pass "ADV-26 (K8S-06): DNSEndpoint CNAME target, TTL=1, and cloudflare-proxied annotations verified"
	else
		fail "ADV-26 (K8S-06): DNSEndpoint Cloudflare Tunnel configuration check failed"
	fi
}

test_tier5_adv_k8s_07_argocd_secret_template_exclusion() {
	if python3 -c '
import yaml
d = yaml.safe_load(open("gitops/argocd/applications/gods-eye-view.yaml"))
src = d["spec"]["source"]

assert src.get("path") == "gitops/argocd/platform/gods-eye-view", "source.path mismatch"
assert src.get("targetRevision") == "HEAD", "targetRevision must be HEAD"
direc = src.get("directory", {})
assert direc.get("recurse") is True, "directory.recurse must be true"
assert "secrets.template.yaml" in direc.get("exclude", ""), "directory.exclude must exclude secrets.template.yaml to prevent secret destruction"
' 2>/dev/null; then
		pass "ADV-27 (K8S-07): ArgoCD Application explicitly excludes secrets.template.yaml from automated reconciliation"
	else
		fail "ADV-27 (K8S-07): ArgoCD Application secrets.template.yaml exclusion check failed"
	fi
}

test_tier5_adv_k8s_08_argocd_sync_options_resilience() {
	if python3 -c '
import yaml
d = yaml.safe_load(open("gitops/argocd/applications/gods-eye-view.yaml"))
sp = d["spec"]["syncPolicy"]

sync_opts = sp.get("syncOptions", [])
assert "ServerSideApply=true" in sync_opts, "ServerSideApply=true required to prevent last-applied drift"
assert "CreateNamespace=true" in sync_opts, "CreateNamespace=true required"
auto = sp.get("automated", {})
assert auto.get("prune") is True, "automated.prune must be true"
assert auto.get("selfHeal") is True, "automated.selfHeal must be true"

ann = d["metadata"].get("annotations", {})
assert ann.get("argocd.argoproj.io/sync-wave") == "2", "sync-wave annotation must be 2"
' 2>/dev/null; then
		pass "ADV-28 (K8S-08): ArgoCD Application syncOptions enforce ServerSideApply=true, prune, selfHeal, and sync-wave 2"
	else
		fail "ADV-28 (K8S-08): ArgoCD syncPolicy resilience check failed"
	fi
}

test_tier5_adv_k8s_09_appproject_rbac_whitelist_confinement() {
	if python3 -c '
import yaml
d = yaml.safe_load(open("gitops/argocd/projects/gods-eye-view-project.yaml"))
spec = d["spec"]

dest = spec.get("destinations", [])
assert len(dest) == 1, "Destinations must be confined to exactly 1 cluster/namespace"
assert dest[0].get("namespace") == "gods-eye-view", "Destination namespace must be gods-eye-view"
assert dest[0].get("server") == "https://kubernetes.default.svc", "Destination server must be local cluster"

c_white = spec.get("clusterResourceWhitelist", [])
assert len(c_white) == 1 and c_white[0].get("kind") == "Namespace", "Only Namespace allowed in clusterResourceWhitelist"

ns_white = spec.get("namespaceResourceWhitelist", [])
allowed_kinds = {item["kind"] for item in ns_white}
expected_kinds = {"Deployment", "Service", "DNSEndpoint", "HTTPRoute", "SealedSecret", "Secret"}
assert allowed_kinds == expected_kinds, f"namespaceResourceWhitelist mismatch: {allowed_kinds}"

for item in ns_white:
    assert item.get("kind") != "*" and item.get("group") != "*", "Wildcard kind/group forbidden in AppProject"
' 2>/dev/null; then
		pass "ADV-29 (K8S-09): AppProject RBAC whitelists strictly confined without wildcards or privilege escalation"
	else
		fail "ADV-29 (K8S-09): AppProject RBAC whitelist confinement check failed"
	fi
}

test_tier5_adv_k8s_10_secrets_template_safety_and_schema() {
	if python3 -c '
import yaml, re
sec = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/secrets.template.yaml"))
dep = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/deployment.yaml"))

assert sec.get("kind") == "Secret", "kind must be Secret"
assert sec.get("type") == "Opaque", "type must be Opaque"

sdata = sec.get("stringData", {})
required_keys = ["GOOGLE_MAPS_API_KEY", "OPENAI_API_KEY", "CESIUM_ION_ACCESS_TOKEN", "AISSTREAM_API_KEY"]
for k in required_keys:
    assert k in sdata, f"Required key {k} missing from secrets template"
    v = sdata[k]
    assert v.startswith("<") and v.endswith(">"), f"Value for {k} must be placeholder, got {v}"
    assert not re.match(r"^sk-[0-9a-zA-Z]{20,}", v), f"Real OpenAI API key detected in {k}"
    assert not re.match(r"^AIza[0-9a-zA-Z_-]{30,}", v), f"Real Google API key detected in {k}"

env_from = dep["spec"]["template"]["spec"]["containers"][0].get("envFrom", [])
found_ref = False
for ef in env_from:
    sr = ef.get("secretRef", {})
    if sr.get("name") == "gods-eye-view-secrets":
        found_ref = True
        assert sr.get("optional") is True, "secretRef must specify optional: true"
assert found_ref, "Deployment missing secretRef gods-eye-view-secrets"
' 2>/dev/null; then
		pass "ADV-30 (K8S-10): Secrets template contains zero committed secrets and deployment references secrets optionally"
	else
		fail "ADV-30 (K8S-10): Secrets template schema and safety check failed"
	fi
}

test_tier5_adv_cnt_11_dockerignore_coverage_and_leak_prevention() {
	if python3 -c '
import os
p = "apps/web/gods-eye-view/.dockerignore"
assert os.path.isfile(p), ".dockerignore must exist"
lines = [l.strip() for l in open(p) if l.strip() and not l.startswith("#")]

for required in ["node_modules", ".git", "bazel-*", ".env*", "*.pem", "*.key", "secrets*"]:
    assert required in lines, f"{required} must be in .dockerignore"
' 2>/dev/null; then
		pass "ADV-31 (CNT-11): Dockerignore covers sensitive patterns (.env*, *.pem, *.key, secrets*) and build artifacts"
	else
		fail "ADV-31 (CNT-11): Dockerignore coverage and sensitive file pattern check failed"
	fi
}

test_tier5_adv_cnt_12_dockerfile_user_uid_sync() {
	if python3 -c '
import yaml, re
df_content = open("apps/web/gods-eye-view/Dockerfile").read()
dep = yaml.safe_load(open("gitops/argocd/platform/gods-eye-view/deployment.yaml"))

u_match = re.search(r"useradd\s+-[^\n]*?-u\s+(\d+)", df_content)
g_match = re.search(r"groupadd\s+-[^\n]*?-g\s+(\d+)", df_content)
assert u_match and g_match, "useradd -u and groupadd -g required in Dockerfile"

df_uid = int(u_match.group(1))
df_gid = int(g_match.group(1))

sec = dep["spec"]["template"]["spec"]["securityContext"]
k8s_user = sec.get("runAsUser")
k8s_group = sec.get("runAsGroup")
k8s_fs = sec.get("fsGroup")

assert df_uid == k8s_user, f"UID mismatch: Dockerfile {df_uid} vs Deployment {k8s_user}"
assert df_gid == k8s_group, f"GID mismatch: Dockerfile {df_gid} vs Deployment {k8s_group}"
assert df_gid == k8s_fs, f"fsGroup mismatch: Dockerfile {df_gid} vs Deployment {k8s_fs}"
assert "USER nodejs" in df_content or f"USER {df_uid}" in df_content, "Dockerfile must set non-root USER"
' 2>/dev/null; then
		pass "ADV-32 (CNT-12): Dockerfile UID/GID 1001 strictly synchronised with Deployment runAsUser, runAsGroup, fsGroup"
	else
		fail "ADV-32 (CNT-12): Dockerfile UID/GID synchronization check failed"
	fi
}

test_tier5_adv_cnt_13_dockerfile_multistage_and_healthcheck() {
	if python3 -c '
import re
df = open("apps/web/gods-eye-view/Dockerfile").read()

stages = re.findall(r"^FROM\s+([^\s]+)\s+AS\s+([^\s]+)", df, re.MULTILINE)
assert len(stages) >= 2, "Dockerfile must be multi-stage"
build_stage = [s for s in stages if s[1] == "build"][0]
runtime_stage = [s for s in stages if s[1] == "runtime"][0]

assert build_stage[0].startswith("node:22"), "Build stage must use Node 22"
assert runtime_stage[0].startswith("node:22"), "Runtime stage must use Node 22"

assert "pnpm install --prod" in df, "Runtime stage must install --prod only"
assert "EXPOSE 8080" in df, "Dockerfile must EXPOSE 8080"
assert "HEALTHCHECK" in df, "Dockerfile must define HEALTHCHECK probe"
assert "curl -f http://localhost:8080/healthz" in df, "HEALTHCHECK must probe /healthz on 8080"
' 2>/dev/null; then
		pass "ADV-33 (CNT-13): Dockerfile multi-stage separation, prod-only dependencies, and container healthcheck verified"
	else
		fail "ADV-33 (CNT-13): Dockerfile multi-stage and healthcheck check failed"
	fi
}

test_tier5_adv_ci_14_workflow_security_least_privilege() {
	if python3 -c '
import yaml
wf = yaml.safe_load(open(".github/workflows/gods-eye-view-image.yaml"))

perms = wf.get("permissions", {})
assert perms.get("contents") == "read", "permissions.contents must be read"
assert perms.get("packages") == "write", "permissions.packages must be write"
assert len(perms) == 2, f"Excess permissions found: {perms}"

conc = wf.get("concurrency", {})
assert "cancel-in-progress" in conc, "cancel-in-progress missing from concurrency"
assert conc["cancel-in-progress"] == "${{ github.event_name == '\''pull_request'\'' }}"

job = wf["jobs"]["image"]
assert job.get("timeout-minutes") is not None and job.get("timeout-minutes") <= 30, "timeout-minutes must be <= 30"

steps = job.get("steps", [])
login_steps = [s for s in steps if "Log in to GHCR" in s.get("name", "")]
assert len(login_steps) == 1, "Log in to GHCR step missing"
assert "${{ github.event_name != '\''pull_request'\'' }}" in login_steps[0].get("if", ""), "Login must be skipped on PR"

build_steps = [s for s in steps if "Build and push" in s.get("name", "")]
assert len(build_steps) == 1, "Build and push step missing"
with_opts = build_steps[0].get("with", {})
assert "${{ github.event_name != '\''pull_request'\'' }}" in str(with_opts.get("push", "")), "Push must be disabled on PR"
' 2>/dev/null; then
		pass "ADV-34 (CI-14): CI workflow enforces least-privilege tokens, PR push blocking, and timeout bounding"
	else
		fail "ADV-34 (CI-14): CI workflow least-privilege security check failed"
	fi
}

test_tier5_adv_ci_15_workflow_scoped_path_triggers() {
	if python3 -c '
import yaml
wf = yaml.safe_load(open(".github/workflows/gods-eye-view-image.yaml"))

on_events = wf.get(True) or wf.get("on") or {}
assert "push" in on_events, "push event missing"
assert "pull_request" in on_events, "pull_request event missing"
assert "workflow_dispatch" in on_events, "workflow_dispatch missing"

push_branches = on_events["push"].get("branches", [])
assert push_branches == ["main"], f"push branches must be [main], got {push_branches}"

expected_paths = {
    "apps/web/gods-eye-view/**",
    ".github/workflows/gods-eye-view-image.yaml",
    "pnpm-lock.yaml",
    "pnpm-workspace.yaml"
}
push_paths = set(on_events["push"].get("paths", []))
assert push_paths == expected_paths, f"push paths mismatch: {push_paths}"

pr_paths = set(on_events["pull_request"].get("paths", []))
assert pr_paths == expected_paths, f"pull_request paths mismatch: {pr_paths}"
' 2>/dev/null; then
		pass "ADV-35 (CI-15): CI workflow trigger paths strictly confined to app subpath, workflow, and lockfiles"
	else
		fail "ADV-35 (CI-15): CI workflow trigger path scoping check failed"
	fi
}

test_tier5_adv_bzl_16_package_group_architectural_layer() {
	if python3 -c '
content = open("tools/boundaries/package_groups.bzl").read()

assert "\"//apps/...\"" in content or "'\''//apps/...'\''" in content, "//apps/... missing from package_groups.bzl"
assert "LAYER_APPS = 3" in content, "LAYER_APPS must be 3"
assert "LAYER_APPS: \"apps\"" in content or "LAYER_APPS: '\''apps'\''" in content, "apps layer mapping missing"
' 2>/dev/null; then
		pass "ADV-36 (BZL-16): Bazel architectural layer boundaries place //apps/... at LAYER_APPS = 3"
	else
		fail "ADV-36 (BZL-16): Bazel architectural layer boundary check failed"
	fi
}

test_tier5_adv_bzl_17_gazelle_exclusion_and_build_integrity() {
	if python3 -c '
rb_content = open("BUILD").read()
ab_content = open("apps/web/gods-eye-view/BUILD").read()

assert "# gazelle:exclude apps" in rb_content, "Root BUILD missing # gazelle:exclude apps"
assert "# gazelle:ignore" in ab_content, "apps/web/gods-eye-view/BUILD missing # gazelle:ignore"

for rt in ["vite.vite", "js_test", "sh_test", "doctor", "pipeline_unit"]:
    assert rt in ab_content, f"Rule {rt} missing from apps/web/gods-eye-view/BUILD"

assert ":unit_tests" in ab_content, ":unit_tests missing from pipeline_unit"
assert ":cesium_assets_test" in ab_content, ":cesium_assets_test missing from pipeline_unit"
assert ":build" in ab_content, ":build missing from pipeline_unit"
' 2>/dev/null; then
		pass "ADV-37 (BZL-17): Gazelle exclusions protect hand-authored Vite build rules and pipeline_unit is comprehensive"
	else
		fail "ADV-37 (BZL-17): Gazelle exclusion and build integrity check failed"
	fi
}

test_tier5_adv_k8s_01_pod_security_restricted
test_tier5_adv_k8s_02_volume_mount_isolation
test_tier5_adv_k8s_03_probe_threshold_safety
test_tier5_adv_k8s_04_httproute_gateway_ref_integrity
test_tier5_adv_k8s_05_httproute_backend_service_parity
test_tier5_adv_k8s_06_dnsendpoint_tunnel_cname_coherence
test_tier5_adv_k8s_07_argocd_secret_template_exclusion
test_tier5_adv_k8s_08_argocd_sync_options_resilience
test_tier5_adv_k8s_09_appproject_rbac_whitelist_confinement
test_tier5_adv_k8s_10_secrets_template_safety_and_schema
test_tier5_adv_cnt_11_dockerignore_coverage_and_leak_prevention
test_tier5_adv_cnt_12_dockerfile_user_uid_sync
test_tier5_adv_cnt_13_dockerfile_multistage_and_healthcheck
test_tier5_adv_ci_14_workflow_security_least_privilege
test_tier5_adv_ci_15_workflow_scoped_path_triggers
test_tier5_adv_bzl_16_package_group_architectural_layer
test_tier5_adv_bzl_17_gazelle_exclusion_and_build_integrity

echo "================================================================================"
echo " Tier 5 Summary: ${PASSED_TESTS}/${TOTAL_TESTS} passed (${SKIPPED_TESTS} skipped, ${FAILED_TESTS} failed)"
echo "================================================================================"

if [ "$FAILED_TESTS" -gt 0 ]; then
	exit 1
fi
exit 0
