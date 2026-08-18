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
#
# Mint AND seal the read-only ArgoCD token that the Backstage portal's ArgoCD
# cards authenticate with (docs/backstage-argocd.md). One step, no credential
# ever passes through a human's clipboard or shell history — unlike
# seal-alert-ntfy, which takes a password you already hold, this target creates
# the credential itself and pipes it straight into kubeseal.
#
#   bazel run //tools/gitops:seal-argocd-backstage-token
#   bazel run //tools/gitops:seal-argocd-backstage-token -- --apply
#   bazel run //tools/gitops:seal-argocd-backstage-token -- --expires-in 8760h
#
# The identity is the `backstage` PROJECT ROLE on platform-project, declared in
# gitops/argocd/projects/platform.yaml. That file must be merged AND synced
# before this runs — the role has to exist server-side to mint against. This
# script fails with a pointed message rather than a raw 404 when it does not.
#
# Scope, verified against the live server (v3.4.4), not assumed:
#   - reads all Applications in every project (via `policy.default: role:readonly`
#     in argocd-rbac-cm, NOT via the role's own policy)
#   - cannot sync, delete or roll back: those return 403 "permission denied ...
#     sub: proj:platform-project:backstage"
#
# No expiry by default, matching grafana-backstage-token: an expiring token
# silently breaks the cards months later with no failing gate to catch it. Pass
# --expires-in to opt into rotation.
set -euo pipefail

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"

NS=backstage
SECRET=argocd-backstage-token
KEY=ARGOCD_TOKEN
PROJECT=platform-project
ROLE=backstage
ARGOCD_URL="${ARGOCD_SERVER_URL:-https://argocd.lab.ipv1337.dev}"
OUT="gitops/argocd/platform/sealed-secrets-manifests/${SECRET}.sealedsecret.yaml"
CTRL_NS="${SEALED_SECRETS_NAMESPACE:-sealed-secrets}"
CTRL_NAME="${SEALED_SECRETS_CONTROLLER:-sealed-secrets-controller}"

APPLY=0
EXPIRES_IN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --expires-in) shift; EXPIRES_IN="${1:?--expires-in needs a duration, e.g. 8760h}" ;;
    *) echo "ERROR: unknown argument '$1' (expected --apply and/or --expires-in DURATION)" >&2; exit 2 ;;
  esac
  shift
done

for c in kubectl kubeseal curl python3; do
  command -v "$c" >/dev/null 2>&1 || { echo "ERROR: $c not found on PATH." >&2; exit 1; }
done

cd "${BUILD_WORKSPACE_DIRECTORY:?this target must be run via 'bazel run', not 'bazel build'}"

# Admin session, needed only to MINT. Prefer a caller-supplied token; otherwise
# read the bootstrap admin password straight from the cluster (self-service:
# anyone who can run this already has cluster-admin kubeconfig). The password is
# passed to curl as a JSON body built in python from the environment, never as
# an argv element where it would show up in `ps`.
if [ -n "${ARGOCD_AUTH_TOKEN:-}" ]; then
  SESSION="$ARGOCD_AUTH_TOKEN"
else
  ARGO_PW="$(kubectl --context "$KCTX" get secret argocd-initial-admin-secret -n argocd \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"
  if [ -z "$ARGO_PW" ]; then
    echo "ERROR: no ARGOCD_AUTH_TOKEN set and argocd-initial-admin-secret is absent." >&2
    echo "       Set ARGOCD_AUTH_TOKEN=\$(argocd account generate-token ...) and re-run." >&2
    exit 1
  fi
  export ARGO_PW
  SESSION="$(python3 -c 'import os,json;print(json.dumps({"username":"admin","password":os.environ["ARGO_PW"]}))' \
    | curl -sS -X POST "${ARGOCD_URL}/api/v1/session" -H 'Content-Type: application/json' -d @- \
    | python3 -c 'import sys,json;print(json.load(sys.stdin).get("token",""))')"
  unset ARGO_PW
fi
[ -n "$SESSION" ] || { echo "ERROR: could not authenticate to ${ARGOCD_URL}." >&2; exit 1; }

# Fail loudly when the role is missing — that means platform.yaml has not merged
# or app-of-projects has not synced yet, which is the single most likely reason
# for this target to fail and is invisible in a raw HTTP 404.
if ! kubectl --context "$KCTX" get appproject "$PROJECT" -n argocd \
     -o jsonpath='{.spec.roles[*].name}' 2>/dev/null | tr ' ' '\n' | grep -qx "$ROLE"; then
  echo "ERROR: role '${ROLE}' does not exist on AppProject '${PROJECT}'." >&2
  echo "       Merge gitops/argocd/projects/platform.yaml and let app-of-projects sync," >&2
  echo "       then re-run. (kubectl get appproject ${PROJECT} -n argocd -o yaml)" >&2
  exit 1
fi

BODY='{}'
[ -n "$EXPIRES_IN" ] && BODY="$(python3 -c 'import sys,json;print(json.dumps({"expiresIn":sys.argv[1]}))' "$EXPIRES_IN")"

# Mint. The token is captured into a variable and piped onward; it is never
# echoed, never written unencrypted, and never passed as an argv element.
TOKEN="$(curl -sS -X POST "${ARGOCD_URL}/api/v1/projects/${PROJECT}/roles/${ROLE}/token" \
  -H "Authorization: Bearer ${SESSION}" -H 'Content-Type: application/json' -d "$BODY" \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);sys.stderr.write(d.get("error","")[:200]);print(d.get("token",""))')"
[ -n "$TOKEN" ] || { echo "ERROR: token mint returned no token (see message above)." >&2; exit 1; }

# License header first: tools/license requires one on every committed file and
# kubeseal emits none, so without this every rotation regenerates a file CI rejects.
cat > "$OUT" <<'HEADER'
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
#
# Generated by `bazel run //tools/gitops:seal-argocd-backstage-token`.
# Read-only ArgoCD project-role token for the Backstage ArgoCD cards.
HEADER
printf '%s' "$TOKEN" \
  | kubectl --context "$KCTX" create secret generic "$SECRET" -n "$NS" \
      --dry-run=client --from-file="${KEY}=/dev/stdin" -o yaml \
  | kubeseal --format yaml \
      --controller-namespace "$CTRL_NS" --controller-name "$CTRL_NAME" \
  >> "$OUT"
unset TOKEN
echo "✓ minted + sealed → $OUT (SealedSecret ${NS}/${SECRET}, key ${KEY})"

if [ "$APPLY" -eq 1 ]; then
  kubectl --context "$KCTX" apply -f "$OUT"
  echo "✓ applied — the controller will materialize ${NS}/${SECRET}"
else
  echo "next: commit ${OUT} (ArgoCD applies it), or re-run with --apply to apply now"
fi
