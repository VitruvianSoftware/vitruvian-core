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

# ensure-site-verification_test.sh — hermetic regression guard for
# ensure-site-verification.sh. Drives the REAL script end-to-end against a
# local mock of the three external APIs (Site Verification, Cloudflare,
# Google DoH), asserting:
#   1. bootstrap: getToken -> Cloudflare TXT create -> DNS poll -> insert ->
#      owners update unions the deploy SAs alongside pre-existing owners;
#   2. idempotence: a second run with converged state performs NO writes;
#   3. the no-customDomain no-op gate.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/ensure-site-verification.sh"

work="$(mktemp -d)"
trap '{ [ -n "${server_pid:-}" ] && kill "$server_pid" && wait "$server_pid"; } 2>/dev/null; rm -rf "$work"' EXIT

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }
assert_eq() { # assert_eq <name> <actual> <expected>
  if [ "$2" = "$3" ]; then pass "$1"; else
    printf '  ✗ %s — got %q, want %q\n' "$1" "$2" "$3" >&2; fails=$((fails + 1))
  fi
}

# --- fixture app dir ---------------------------------------------------------
app="$work/app"
mkdir -p "$app"
cat >"$app/Pulumi.development.yaml" <<'EOF'
config:
  oauth-user-inspector:project: prj-d-test-1234
  oauth-user-inspector:customDomain: oauth-inspector.dev.example.test
  oauth-user-inspector:cloudflareZone: example.test
EOF
cat >"$app/Pulumi.production.yaml" <<'EOF'
config:
  oauth-user-inspector:project: "prj-p-test-5678"
  oauth-user-inspector:customDomain: "oauth-inspector.example.test"
  oauth-user-inspector:cloudflareZone: "example.test"
EOF
# An env WITHOUT a custom domain must contribute nothing.
cat >"$app/Pulumi.nonproduction.yaml" <<'EOF'
config:
  oauth-user-inspector:project: prj-n-test-9999
EOF

# --- mock server -------------------------------------------------------------
# State lives in $MOCK_STATE (JSON) so assertions can inspect exactly which
# writes happened. The mock enforces the REAL contract ordering: insert fails
# until the verification TXT exists in the (mock) Cloudflare zone, and the DoH
# endpoint only "propagates" records that Cloudflare holds.
cat >"$work/mock_server.py" <<'PYEOF'
import json, os, re, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

STATE_PATH = os.environ["MOCK_STATE"]

def load():
    with open(STATE_PATH) as f:
        return json.load(f)

def save(s):
    with open(STATE_PATH, "w") as f:
        json.dump(s, f, indent=1)

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def body_json(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def resource(self, s):
        return {"id": "dns%3A%2F%2Fexample.test",
                "site": {"identifier": "example.test", "type": "INET_DOMAIN"},
                "owners": s["owners"]}

    def do_GET(self):
        s = load()
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path == "/siteVerification/v1/webResource/dns%3A%2F%2Fexample.test" or \
           urllib.parse.unquote(u.path) == "/siteVerification/v1/webResource/dns://example.test":
            s["counts"]["sv_get"] += 1; save(s)
            if s["verified"]:
                return self.reply(200, self.resource(s))
            return self.reply(404, {"error": {"code": 404, "message": "not found"}})
        if u.path == "/client/v4/zones":
            return self.reply(200, {"result": [{"id": "zid1"}]} if q.get("name") == ["example.test"] else {"result": []})
        if u.path == "/client/v4/zones/zid1/dns_records":
            return self.reply(200, {"result": s["cf_records"]})
        if u.path == "/resolve":
            if q.get("name") == ["example.test"] and q.get("type") == ["TXT"]:
                ans = [{"data": '"%s"' % r["content"]} for r in s["cf_records"]]
                return self.reply(200, {"Answer": ans})
            return self.reply(200, {})
        return self.reply(404, {"error": {"message": "unknown GET " + self.path}})

    def do_POST(self):
        s = load()
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path == "/siteVerification/v1/token":
            s["counts"]["sv_gettoken"] += 1; save(s)
            b = self.body_json()
            if b.get("site", {}).get("type") != "INET_DOMAIN":
                return self.reply(400, {"error": {"message": "bad site type"}})
            # The real API rejects the wrong method name for domains; accept
            # both here since the script tolerates either.
            if b.get("verificationMethod") not in ("DNS_TXT", "DNS"):
                return self.reply(400, {"error": {"message": "bad method"}})
            return self.reply(200, {"method": "DNS_TXT", "token": "tok-abc-123"})
        if u.path == "/siteVerification/v1/webResource":
            s["counts"]["sv_insert"] += 1
            want = "google-site-verification=tok-abc-123"
            if any(r["content"] == want for r in s["cf_records"]):
                s["verified"] = True
                if "build-sa@prj-c-test.iam.gserviceaccount.com" not in s["owners"]:
                    s["owners"].append("build-sa@prj-c-test.iam.gserviceaccount.com")
                save(s)
                return self.reply(200, self.resource(s))
            save(s)
            return self.reply(400, {"error": {"message": "TXT not found"}})
        if u.path == "/client/v4/zones/zid1/dns_records":
            s["counts"]["cf_create"] += 1
            b = self.body_json()
            s["cf_records"].append({"type": b["type"], "name": b["name"], "content": b["content"]})
            save(s)
            return self.reply(200, {"success": True, "result": b})
        return self.reply(404, {"error": {"message": "unknown POST " + self.path}})

    def do_PUT(self):
        s = load()
        u = urllib.parse.urlparse(self.path)
        if u.path.startswith("/siteVerification/v1/webResource/"):
            s["counts"]["sv_update"] += 1
            b = self.body_json()
            if not s["verified"]:
                save(s)
                return self.reply(403, {"error": {"message": "not an owner"}})
            s["owners"] = b.get("owners", [])
            save(s)
            return self.reply(200, self.resource(s))
        return self.reply(404, {"error": {"message": "unknown PUT " + self.path}})

srv = HTTPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
PYEOF

export MOCK_STATE="$work/state.json"
cat >"$MOCK_STATE" <<'EOF'
{"verified": false,
 "owners": ["james@example.test"],
 "cf_records": [{"type": "TXT", "name": "example.test", "content": "v=spf1 -all"}],
 "counts": {"sv_get": 0, "sv_gettoken": 0, "sv_insert": 0, "sv_update": 0, "cf_create": 0}}
EOF

python3 "$work/mock_server.py" >"$work/port" 2>"$work/server.err" &
server_pid=$!
for _ in $(seq 1 50); do
  [ -s "$work/port" ] && break
  sleep 0.1
done
port="$(cat "$work/port")"
base="http://127.0.0.1:$port"

run_script() {
  APP_DIR="$app" \
    SITEVERIFY_ACCESS_TOKEN="fake-oauth-token" \
    CLOUDFLARE_API_TOKEN="fake-cf-token" \
    SITEVERIFY_API_BASE="$base/siteVerification/v1" \
    CLOUDFLARE_API_BASE="$base/client/v4" \
    DOH_API_BASE="$base" \
    bash "$SCRIPT"
}

echo "test 1: bootstrap converges verification + owners"
if out="$(run_script 2>&1)"; then pass "exit 0"; else fail "exit 0 — output: $out"; fi
state() { jq -r "$1" "$MOCK_STATE"; }
assert_eq "TXT created once" "$(state '.counts.cf_create')" "1"
assert_eq "TXT record content" \
  "$(state '[.cf_records[].content] | any(. == "google-site-verification=tok-abc-123")')" "true"
assert_eq "pre-existing TXT untouched" \
  "$(state '[.cf_records[].content] | any(. == "v=spf1 -all")')" "true"
assert_eq "verified" "$(state '.verified')" "true"
assert_eq "owners updated once" "$(state '.counts.sv_update')" "1"
for o in \
  "oauth-user-inspector-deploy@prj-d-test-1234.iam.gserviceaccount.com" \
  "oauth-user-inspector-deploy@prj-p-test-5678.iam.gserviceaccount.com" \
  "build-sa@prj-c-test.iam.gserviceaccount.com" \
  "james@example.test"; do
  assert_eq "owner kept/added: $o" "$(jq -r --arg o "$o" '.owners | index($o) != null' "$MOCK_STATE")" "true"
done
assert_eq "no-domain env contributed no owner" \
  "$(jq -r '.owners | index("oauth-user-inspector-deploy@prj-n-test-9999.iam.gserviceaccount.com") != null' "$MOCK_STATE")" "false"

echo "test 2: second run is a pure no-op (no writes)"
if out="$(run_script 2>&1)"; then pass "exit 0"; else fail "exit 0 — output: $out"; fi
assert_eq "no new TXT" "$(state '.counts.cf_create')" "1"
assert_eq "no new getToken" "$(state '.counts.sv_gettoken')" "1"
assert_eq "no new insert" "$(state '.counts.sv_insert')" "1"
assert_eq "no new owners update" "$(state '.counts.sv_update')" "1"
case "$out" in
  *"all deploy SAs already owners; no-op"*) pass "no-op message" ;;
  *) fail "no-op message — output: $out" ;;
esac

echo "test 3: no customDomain anywhere -> clean exit, no credentials needed"
empty="$work/empty-app"; mkdir -p "$empty"
cat >"$empty/Pulumi.development.yaml" <<'EOF'
config:
  oauth-user-inspector:project: prj-d-test-1234
EOF
if out="$(APP_DIR="$empty" bash "$SCRIPT" 2>&1)"; then pass "exit 0"; else fail "exit 0 — output: $out"; fi
case "$out" in
  *"nothing to do"*) pass "gate message" ;;
  *) fail "gate message — output: $out" ;;
esac

if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails assertion(s)" >&2
  exit 1
fi
echo "ALL PASS"
