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
# Live gate for the CI collector. 1) an unsigned POST must get 400 -- the
# receiver accepts EVERYTHING when its secret is empty, so this proves the
# secret is really set; 2) a correctly signed sample workflow_run event must
# produce a metric (Prometheus) and a trace (Tempo) without the committer
# email. The secret is read from the cluster into a 0600 temp file and never
# printed. Spec: docs/superpowers/specs/2026-09-28-cicd-telemetry-design.md
#   bazel run //tools/gitops:cicd-telemetry-smoke
set -euo pipefail

sign() { # sign <secret-file> <payload-file> -> sha256=<hex>
  printf 'sha256=%s\n' "$(openssl dgst -sha256 -hmac "$(cat "$1")" -r < "$2" | cut -d' ' -f1)"
}
# shellcheck disable=SC2317 # exit is reached when run, return when sourced
if [ -n "${SMOKE_LIB_ONLY:-}" ]; then return 0 2>/dev/null || exit 0; fi

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"; export KUBECONFIG
URL="${SMOKE_URL:-https://github-otel.ipv1337.dev/events}"
RUN_NAME="cicd-telemetry smoke test"
for c in curl jq kubectl openssl; do
  command -v "$c" >/dev/null 2>&1 || { echo "ERROR: $c not found on PATH." >&2; exit 1; }
done
W="$(umask 077; mktemp -d)"; trap 'rm -rf "$W"' EXIT

# 1. unsigned -> 400
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'X-GitHub-Event: workflow_run' \
  -H 'Content-Type: application/json' --data '{}' "$URL")"
[ "$code" = 400 ] || { echo "✗ unsigned request got $code, want 400 -- is the webhook secret empty?" >&2; exit 1; }
echo "✓ unsigned request rejected (400)"

# 2. signed sample event -> 200
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
start="$(date -u -v-3M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-3 min' +%Y-%m-%dT%H:%M:%SZ)"
run_id="$(date +%s)"
cat > "$W/payload" <<JSON
{"action":"completed","workflow_run":{"id":${run_id},"name":"${RUN_NAME}","run_attempt":1,"status":"completed","conclusion":"success","run_started_at":"${start}","created_at":"${start}","updated_at":"${now}","html_url":"https://github.com/VitruvianSoftware/vitruvian-core/actions/runs/${run_id}","head_branch":"main","head_sha":"0000000000000000000000000000000000000000","head_commit":{"committer":{"name":"smoke","email":"smoke@example.invalid"}}},"repository":{"name":"vitruvian-core","full_name":"VitruvianSoftware/vitruvian-core","owner":{"login":"VitruvianSoftware"}},"sender":{"login":"cicd-telemetry-smoke"}}
JSON
kubectl -n cicd-telemetry get secret github-otel-webhook -o jsonpath='{.data.GITHUB_WEBHOOK_SECRET}' | base64 -d > "$W/secret"
[ -s "$W/secret" ] || { echo "✗ Secret cicd-telemetry/github-otel-webhook is empty or missing" >&2; exit 1; }
sig="$(sign "$W/secret" "$W/payload")"
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'X-GitHub-Event: workflow_run' \
  -H "X-GitHub-Delivery: smoke-${run_id}" -H 'Content-Type: application/json' \
  -H "X-Hub-Signature-256: ${sig}" --data-binary @"$W/payload" "$URL")"
[ "$code" = 200 ] || { echo "✗ signed request got $code, want 200" >&2; exit 1; }
echo "✓ signed sample event accepted (200)"

# 3. metric appears (spanmetrics flushes every ~15s; allow 2 min)
q="cicd_calls_total{cicd_pipeline_name=\"${RUN_NAME}\"}"
n=0
for _ in $(seq 1 24); do
  n="$(kubectl -n monitoring exec prometheus-server-0 -c prometheus-server -- \
        wget -qO- "localhost:9090/api/v1/query?query=$(printf '%s' "$q" | jq -sRr @uri)" | jq '.data.result|length')"
  [ "${n:-0}" -gt 0 ] && break; sleep 5
done
[ "${n:-0}" -gt 0 ] || { echo "✗ no ${q} in Prometheus after 2 minutes" >&2; exit 1; }
echo "✓ metric in Prometheus"

# 4. trace appears in Tempo, WITHOUT the committer email
tq="$(printf '%s' '{ resource.service.name = "github-actions" && name = "'"${RUN_NAME}"'" }' | jq -sRr @uri)"
tid=""
for _ in $(seq 1 12); do
  res="$(kubectl -n opentelemetry exec tempo-0 -- wget -qO- "localhost:3200/api/search?q=${tq}&limit=1" 2>/dev/null || true)"
  tid="$(jq -r '.traces[0].traceID // empty' <<<"$res" 2>/dev/null || true)"
  [ -n "$tid" ] && break; sleep 5
done
[ -n "$tid" ] || { echo "✗ no trace in Tempo after 1 minute" >&2; exit 1; }
trace="$(kubectl -n opentelemetry exec tempo-0 -- wget -qO- "localhost:3200/api/traces/${tid}")"
if grep -q 'smoke@example.invalid' <<<"$trace"; then echo "✗ committer email reached Tempo" >&2; exit 1; fi
echo "✓ trace in Tempo (${tid}), committer email stripped"
