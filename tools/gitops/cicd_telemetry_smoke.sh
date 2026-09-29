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
# printed. Every run ends with exactly one verdict: "✓ PASS ..." on success or
# a "✗ ..." line on failure -- never a silent exit.
# Spec: docs/superpowers/specs/2026-09-28-cicd-telemetry-design.md
#   bazel run //tools/gitops:cicd-telemetry-smoke
set -euo pipefail

sign() { # sign <secret-file> <payload-file> -> sha256=<hex>
  # The key is read from the file inside python: it never appears on any
  # command line (openssl -hmac would put it in argv, visible in ps).
  python3 - "$1" "$2" <<'PY'
import hashlib, hmac, sys
key = open(sys.argv[1], "rb").read()
body = open(sys.argv[2], "rb").read()
print("sha256=" + hmac.new(key, body, hashlib.sha256).hexdigest())
PY
}
# shellcheck disable=SC2317 # exit is reached when run, return when sourced
if [ -n "${SMOKE_LIB_ONLY:-}" ]; then return 0 2>/dev/null || exit 0; fi

# Under set -e an unexpected failure (a kubectl blip, a pod restarting) would
# otherwise end the run with no verdict at all.
trap 'echo "✗ FAIL: unexpected error (exit $?) at line $LINENO: $BASH_COMMAND" >&2' ERR

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"; export KUBECONFIG
URL="${SMOKE_URL:-https://github-otel.ipv1337.dev/events}"
for c in curl jq kubectl python3; do
  command -v "$c" >/dev/null 2>&1 || { echo "ERROR: $c not found on PATH." >&2; exit 1; }
done
W="$(umask 077; mktemp -d)"; trap 'rm -rf "$W"' EXIT
prom() { # prom <promql> -> first sample value, or 0
  kubectl -n monitoring exec prometheus-server-0 -c prometheus-server -- \
    wget -qO- "localhost:9090/api/v1/query?query=$(printf '%s' "$1" | jq -sRr @uri)" \
    | jq -r '.data.result[0].value[1] // "0"'
}
# Every check below must be caused by THIS run, so the run gets a unique name
# and id. (Two earlier designs passed on stale data, seen live: a trace looked
# up by a fixed name, and a summed counter -- spanmetrics re-sends cumulative
# series every flush and an old pod's series ages out as a new one appears.)
# The CI pipelines dashboard hides names starting "cicd-telemetry smoke".
run_id="$(date +%s)"
RUN_NAME="cicd-telemetry smoke ${run_id}"
q="sum(cicd_calls_total{cicd_pipeline_name=\"${RUN_NAME}\", ci_span_type=\"run\"})"

# 1. unsigned -> 400
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'X-GitHub-Event: workflow_run' \
  -H 'Content-Type: application/json' --data '{}' "$URL")"
[ "$code" = 400 ] || { echo "✗ unsigned request got $code, want 400 -- is the webhook secret empty?" >&2; exit 1; }
echo "✓ unsigned request rejected (400)"

# 2. signed sample event -> 200
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
start="$(date -u -v-3M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-3 min' +%Y-%m-%dT%H:%M:%SZ)"
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
sent_at="$(date +%s)"

# 3. this run's series reaches a count of 1. It can take up to ~2 minutes,
#    measured live: span_metrics reports every 60s, and a new series' FIRST
#    sample is 0 (a start point, so dashboards can count from it) -- the 1
#    only lands on the NEXT report. A fixed 2-minute window failed on a
#    healthy pipeline (seen at 118-119s), so allow 4 minutes by the clock.
#    A failed query is retried like a missing value, not fatal; the last
#    error is reported if it never recovers.
n=0
deadline=$(( sent_at + ${SMOKE_METRIC_WAIT_S:-240} ))
while :; do
  n="$(prom "$q" 2>"$W/prom.err")" || n=0
  awk -v a="$n" 'BEGIN{exit !(a>=1)}' && break
  [ "$(date +%s)" -ge "$deadline" ] && break
  sleep 5
done
awk -v a="$n" 'BEGIN{exit !(a>=1)}' || {
  echo "✗ no run count for '${RUN_NAME}' in Prometheus after $(( $(date +%s) - sent_at ))s" >&2
  [ -s "$W/prom.err" ] && echo "  last query error: $(tail -n 1 "$W/prom.err")" >&2
  exit 1
}
echo "✓ metric for this run in Prometheus (count ${n}, after $(( $(date +%s) - sent_at ))s)"

# 4. trace appears in Tempo, WITHOUT the committer email
tq="$(printf '%s' '{ resource.service.name = "github-actions" && resource.cicd.pipeline.run.id = '"${run_id}"' }' | jq -sRr @uri)"
tid=""
# An explicit window: without start/end Tempo's search can miss a trace this
# fresh (seen live). The sample run starts 3 minutes before it is sent.
# Each Tempo replica keeps its newest traces to itself until they are flushed
# to shared storage (minutes), so ask every replica, not just tempo-0 (a trace
# on tempo-1 was missed -- seen live).
tempo_pods="$(kubectl -n opentelemetry get pods -l app.kubernetes.io/name=tempo -o name)"
tpod=""
for _ in $(seq 1 24); do
  now_s="$(date +%s)"
  for pod in $tempo_pods; do
    res="$(kubectl -n opentelemetry exec "$pod" -- wget -qO- "localhost:3200/api/search?q=${tq}&limit=1&start=$((now_s - 3600))&end=$((now_s + 60))" 2>/dev/null || true)"
    tid="$(jq -r '.traces[0].traceID // empty' <<<"$res" 2>/dev/null || true)"
    [ -n "$tid" ] && { tpod="$pod"; break; }
  done
  [ -n "$tid" ] && break; sleep 5
done
[ -n "$tid" ] || { echo "✗ no trace for run ${run_id} in Tempo after 2 minutes" >&2; exit 1; }
trace="$(kubectl -n opentelemetry exec "$tpod" -- wget -qO- "localhost:3200/api/traces/${tid}")"
if grep -q 'smoke@example.invalid' <<<"$trace"; then echo "✗ committer email reached Tempo" >&2; exit 1; fi
echo "✓ trace for run ${run_id} in Tempo (${tid}, after $(( $(date +%s) - sent_at ))s), committer email stripped"
echo "✓ PASS: CI telemetry works end to end (webhook -> collector -> Prometheus + Tempo)"
