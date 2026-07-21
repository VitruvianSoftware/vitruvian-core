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
#   1. per-env self-verify bootstrap (DEPLOY_ENV set): getToken -> Cloudflare
#      TXT create -> DNS poll -> webResource.insert, scoped to ONLY the
#      calling env's Pulumi.<env>.yaml;
#   2. NO webResource.update PUT is EVER issued — delegation/owner-list
#      writes were removed because the Site Verification API refuses to let a
#      service account modify an owners list containing an external
#      token-verified owner (even a correct union PUT 400s "You cannot
#      unverify this site owner..."). The mock fails any PUT with that same
#      400, so a regression that reintroduces delegation fails the run AND
#      the put-count assertion;
#   3. idempotence: a run against converged state (already a verified owner)
#      performs NO writes;
#   4. the no-customDomain no-op gates (per-env and global).
# The mock's getToken/insert WRITE endpoints REQUIRE x-goog-user-project to
# match the calling env's floating project (SITEVERIFY_QUOTA_PROJECT),
# modelling the real 403 the WRITE calls return when the quota project has not
# enabled the API — the regression guard for the #948 mistake (a read-only GET
# fails on scope first, so it never surfaced that the WRITE path needs the
# enabled quota project).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/ensure-site-verification.sh"

work="$(mktemp -d)"
# Cleanup MUST NOT leak an exit status: `wait` on the SIGTERM'd mock server
# returns 143 (128+15), and an EXIT trap whose last command sets $? makes that
# the script's exit code — a green test run would report 143 to CI (exactly the
# false failure this guards against). Reap the server, discard its status, and
# always return 0 from the trap; the script `exit`s explicitly at the end.
# shellcheck disable=SC2329  # invoked indirectly via `trap cleanup EXIT`
cleanup() {
  if [ -n "${server_pid:-}" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
  return 0
}
trap cleanup EXIT

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
# endpoint only "propagates" records that Cloudflare holds. Ownership is
# CALLER-scoped like the real service: the webResource GET is 200 only once
# THIS caller has self-verified.
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

    def sv_quota_pinned(self):
        # The getToken/insert WRITE calls attribute quota to a project that
        # must have siteverification enabled; the caller pins its OWN floating
        # project via x-goog-user-project. Model the real 403 the WRITE path
        # hits when this is missing ("Site Verification API has not been used
        # in project ... before or it is disabled").
        return self.headers.get("x-goog-user-project") == "prj-d-test-1234"

    def do_GET(self):
        s = load()
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path == "/siteVerification/v1/webResource/dns%3A%2F%2Fexample.test" or \
           urllib.parse.unquote(u.path) == "/siteVerification/v1/webResource/dns://example.test":
            s["counts"]["sv_get"] += 1; save(s)
            # Caller-scoped: 200 only once the CALLING identity has verified.
            if s["caller_verified"]:
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
            if not self.sv_quota_pinned():
                return self.reply(403, {"error": {"message": "Site Verification API has not been used in project 715357066805 before or it is disabled"}})
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
            if not self.sv_quota_pinned():
                return self.reply(403, {"error": {"message": "Site Verification API has not been used in project 715357066805 before or it is disabled"}})
            s["counts"]["sv_insert"] += 1
            want = "google-site-verification=tok-abc-123"
            if any(r["content"] == want for r in s["cf_records"]):
                # Self-verify: the CALLING identity becomes a TOKEN-verified
                # owner (it holds the google-site-verification DNS record).
                # Other owners (the external zone owner) are untouched.
                s["caller_verified"] = True
                caller = "oauth-user-inspector-deploy@prj-d-test-1234.iam.gserviceaccount.com"
                if caller not in s["owners"]:
                    s["owners"].append(caller)
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
            # The script must NEVER issue a webResource.update PUT: the real
            # API refuses ANY owners-list modification by a service account
            # while an external token-verified owner is present — even a
            # correct union that keeps every owner 400s. Count it (the test
            # asserts 0) and fail the call like the live API did.
            s["counts"]["sv_update"] += 1
            save(s)
            return self.reply(400, {"error": {"message":
                "You cannot unverify this site owner until all associated "
                "verification tokens (meta tag, HTML file, Google Analytics "
                "tracking code, Google Tag Manager container code, or DNS "
                "record) are removed from your site."}})
        return self.reply(404, {"error": {"message": "unknown PUT " + self.path}})

srv = HTTPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
PYEOF

export MOCK_STATE="$work/state.json"
cat >"$MOCK_STATE" <<'EOF'
{"caller_verified": false,
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

run_script() { # run_script [deploy-env]; APP_DIR may be overridden by the caller
  APP_DIR="${APP_DIR:-$app}" \
    DEPLOY_ENV="${1:-}" \
    SITEVERIFY_ACCESS_TOKEN="fake-oauth-token" \
    CLOUDFLARE_API_TOKEN="fake-cf-token" \
    SITEVERIFY_QUOTA_PROJECT="prj-d-test-1234" \
    SITEVERIFY_API_BASE="$base/siteVerification/v1" \
    CLOUDFLARE_API_BASE="$base/client/v4" \
    DOH_API_BASE="$base" \
    bash "$SCRIPT"
}

state() { jq -r "$1" "$MOCK_STATE"; }

echo "test 1: per-env bootstrap self-verifies the calling identity (no owner PUT)"
if out="$(run_script development 2>&1)"; then pass "exit 0"; else fail "exit 0 — output: $out"; fi
assert_eq "TXT created once" "$(state '.counts.cf_create')" "1"
assert_eq "TXT record content" \
  "$(state '[.cf_records[].content] | any(. == "google-site-verification=tok-abc-123")')" "true"
assert_eq "pre-existing TXT untouched" \
  "$(state '[.cf_records[].content] | any(. == "v=spf1 -all")')" "true"
assert_eq "caller verified" "$(state '.caller_verified')" "true"
assert_eq "NO webResource.update PUT issued" "$(state '.counts.sv_update')" "0"
assert_eq "external owner untouched" \
  "$(jq -r '.owners | index("james@example.test") != null' "$MOCK_STATE")" "true"
case "$out" in
  *"Pulumi.development.yaml"*) pass "calling env's config read" ;;
  *) fail "calling env's config read — output: $out" ;;
esac
case "$out" in
  *"Pulumi.production.yaml"*) fail "DEPLOY_ENV scoping — another env's config was read: $out" ;;
  *) pass "DEPLOY_ENV scoping (other envs' configs not read)" ;;
esac

echo "test 2: converged run is a pure no-op (already a verified owner; no writes)"
if out="$(run_script development 2>&1)"; then pass "exit 0"; else fail "exit 0 — output: $out"; fi
assert_eq "no new TXT" "$(state '.counts.cf_create')" "1"
assert_eq "no new getToken" "$(state '.counts.sv_gettoken')" "1"
assert_eq "no new insert" "$(state '.counts.sv_insert')" "1"
assert_eq "still no webResource.update PUT" "$(state '.counts.sv_update')" "0"
case "$out" in
  *"already a verified owner"*) pass "no-op message" ;;
  *) fail "no-op message — output: $out" ;;
esac

echo "test 3: unscoped run (no DEPLOY_ENV) scans every env, still no writes"
if out="$(run_script 2>&1)"; then pass "exit 0"; else fail "exit 0 — output: $out"; fi
case "$out" in
  *"Pulumi.development.yaml"*"Pulumi.production.yaml"*) pass "all env configs read" ;;
  *) fail "all env configs read — output: $out" ;;
esac
assert_eq "no new TXT" "$(state '.counts.cf_create')" "1"
assert_eq "no new insert" "$(state '.counts.sv_insert')" "1"
assert_eq "still no webResource.update PUT" "$(state '.counts.sv_update')" "0"

echo "test 4: calling env has no customDomain -> clean no-op, no credentials needed"
if out="$(APP_DIR="$app" DEPLOY_ENV=nonproduction bash "$SCRIPT" 2>&1)"; then pass "exit 0"; else fail "exit 0 — output: $out"; fi
case "$out" in
  *"nothing to do"*) pass "per-env gate message" ;;
  *) fail "per-env gate message — output: $out" ;;
esac

echo "test 5: no customDomain anywhere -> clean exit, no credentials needed"
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

echo "test 6: a NON-oauth config namespace is parsed (the tabula regression)"
# The config namespace is per-app (tabula's app stack uses `tabula-app:`), and
# it is NOT derivable from the Pulumi project name (`pulumi_tabula_app`). A
# namespace-specific parser silently reads NOTHING for every other app, takes
# the "no customDomain" exit-0 path, and reports success while verifying
# nothing — which is exactly how tabula's three custom domains sat at
# Ready=False/"Caller is not authorized to administer the domain" while every
# deploy's ownership step went green.
other="$work/other-app"
mkdir -p "$other"
cat >"$other/Pulumi.development.yaml" <<'EOF'
config:
  gcp:project: prj-d-test-1234
  tabula-app:project: prj-d-test-1234
  tabula-app:customDomain: tabula-api.dev.example.test
  tabula-app:cloudflareZone: example.test
EOF
# Fresh mock state so this exercises the bootstrap path, not test 1's residue.
cat >"$MOCK_STATE" <<'EOF'
{"caller_verified": false,
 "owners": ["james@example.test"],
 "cf_records": [{"type": "TXT", "name": "example.test", "content": "v=spf1 -all"}],
 "counts": {"sv_get": 0, "sv_gettoken": 0, "sv_insert": 0, "sv_update": 0, "cf_create": 0}}
EOF
if out="$(APP_DIR="$other" run_script development 2>&1)"; then pass "exit 0"; else fail "exit 0 — output: $out"; fi
case "$out" in
  *"nothing to do"*) fail "namespace-agnostic parse — took the no-op path: $out" ;;
  *) pass "namespace-agnostic parse (did not silently no-op)" ;;
esac
assert_eq "zone resolved from the tabula-app namespace" \
  "$(state '.counts.cf_create')" "1"
assert_eq "caller verified for the non-oauth app" "$(state '.caller_verified')" "true"

echo "test 7: a customDomain the parser cannot read FAILS LOUDLY (no silent success)"
# The failure mode above was silent because "parsed nothing" and "there is
# nothing to parse" produced the same exit-0 message. Keep them distinguishable:
# if an env file mentions customDomain but no zone was extracted, that is a
# parse bug, and it must not report success.
weird="$work/weird-app"
mkdir -p "$weird"
cat >"$weird/Pulumi.development.yaml" <<'EOF'
config:
  some.app/v2:customDomain:
    value: tabula-api.dev.example.test
EOF
if out="$(APP_DIR="$weird" DEPLOY_ENV=development bash "$SCRIPT" 2>&1)"; then
  fail "unparseable customDomain must be an error — got exit 0: $out"
else
  pass "unparseable customDomain exits non-zero"
fi
case "$out" in
  # Must be the parse-failure message, not the generic "nothing to do" no-op
  # (which also contains the word customDomain).
  *"could not be parsed"*) pass "error is the parse failure, not the no-op" ;;
  *) fail "error is the parse failure, not the no-op — output: $out" ;;
esac

echo "test 8: customDomain without cloudflareZone FAILS rather than guessing a zone"
nozone="$work/nozone-app"
mkdir -p "$nozone"
cat >"$nozone/Pulumi.development.yaml" <<'EOF'
config:
  tabula-app:customDomain: tabula-api.dev.example.test
EOF
if out="$(APP_DIR="$nozone" DEPLOY_ENV=development bash "$SCRIPT" 2>&1)"; then
  fail "missing cloudflareZone must be an error — got exit 0: $out"
else
  pass "missing cloudflareZone exits non-zero"
fi
case "$out" in
  *"refusing to guess"*) pass "refuses to guess the zone" ;;
  *) fail "refuses to guess the zone — output: $out" ;;
esac

if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails assertion(s)" >&2
  exit 1
fi
echo "ALL PASS"
# Explicit success exit: reap the mock server here too (so the EXIT trap's
# `wait` can't be what sets the final status) and exit 0 deterministically.
kill "$server_pid" 2>/dev/null || true
wait "$server_pid" 2>/dev/null || true
server_pid=""
exit 0
