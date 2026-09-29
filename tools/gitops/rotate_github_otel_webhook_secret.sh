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
# Generate the shared secret GitHub signs CI webhook deliveries with, and put
# it in both places that need it -- never printed, never on a command line:
#   1. sealed into gitops/.../sealed-secrets-manifests (Secret
#      cicd-telemetry/github-otel-webhook, key GITHUB_WEBHOOK_SECRET), which the
#      CI collector reads (spec: docs/superpowers/specs/2026-09-28-cicd-telemetry-design.md);
#   2. the GitHub secret OTEL_GITHUB_WEBHOOK_SECRET, in BOTH the Actions store
#      (repo-config apply declares the webhook with it) and the Dependabot store
#      (so previews on Dependabot PRs don't render the webhook as a DELETE).
# Order: seal to a temp file, store in GitHub, and only then move the sealed
# file into git, so a failure never leaves git ahead of GitHub. One case can't
# be undone: if the Actions store takes the new secret and the Dependabot
# store then fails, the two GitHub stores differ (the old value is unknown, so
# it can't be restored). The tool says so and a re-run fixes it.
#
# Rotating without dropping deliveries (GitHub does not retry them) -- see
# docs/operations/key-rotation.md: merge the sealed-file PR, let Argo CD sync,
# restart the collector (it reads the secret at start), run Repo Config Apply,
# then redeliver any failed deliveries from the webhook's delivery log.
#   bazel run //tools/gitops:rotate-github-otel-webhook-secret
set -euo pipefail

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"
GH_REPO="${GH_REPO:-VitruvianSoftware/vitruvian-core}"
NS=cicd-telemetry
SECRET=github-otel-webhook
KEY=GITHUB_WEBHOOK_SECRET
GH_SECRET=OTEL_GITHUB_WEBHOOK_SECRET
OUT="gitops/argocd/platform/sealed-secrets-manifests/${SECRET}.sealedsecret.yaml"
CTRL_NS="${SEALED_SECRETS_NAMESPACE:-sealed-secrets}"
CTRL_NAME="${SEALED_SECRETS_CONTROLLER:-sealed-secrets-controller}"

for c in kubectl kubeseal gh openssl; do
  command -v "$c" >/dev/null 2>&1 || { echo "ERROR: $c not found on PATH." >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not signed in -- run 'gh auth login'." >&2; exit 1; }
cd "${BUILD_WORKSPACE_DIRECTORY:?this target must be run via 'bazel run', not 'bazel build'}"

VALUE="$(openssl rand -hex 32)"
[ "${#VALUE}" = 64 ] || { echo "ERROR: could not generate a secret." >&2; exit 1; }

TMP="$(mktemp "${TMPDIR:-/tmp}/github-otel-webhook.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
# License header first: license-check requires it on every committed file,
# and kubeseal's raw output has none (same as seal_alert_ntfy.sh).
cat > "$TMP" <<'HEADER'
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
HEADER
if ! printf '%s' "$VALUE" \
  | kubectl --context "$KCTX" create secret generic "$SECRET" -n "$NS" \
      --dry-run=client --from-file="${KEY}=/dev/stdin" -o yaml \
  | kubeseal --format yaml --controller-namespace "$CTRL_NS" --controller-name "$CTRL_NAME" \
  >> "$TMP"; then
  echo "ERROR: sealing failed -- nothing was changed." >&2
  exit 1
fi
echo "✓ sealed (Secret ${NS}/${SECRET}, key ${KEY})"

for store in actions dependabot; do
  flag=(); [ "$store" = dependabot ] && flag=(--app dependabot)
  if ! printf '%s' "$VALUE" | gh secret set "$GH_SECRET" --repo "$GH_REPO" ${flag[@]+"${flag[@]}"} >/dev/null; then
    if [ "$store" = dependabot ]; then
      echo "ERROR: could not store ${GH_SECRET} (dependabot). The Actions store already has the NEW secret, so the two GitHub stores now differ -- no sealed file written; re-run this tool to bring everything back in line." >&2
    else
      echo "ERROR: could not store ${GH_SECRET} (actions) -- nothing changed; re-run." >&2
    fi
    exit 1
  fi
  echo "✓ stored ${GH_SECRET} (${store} secrets)"
done
unset VALUE

mv "$TMP" "$OUT"
trap - EXIT
echo "✓ wrote ${OUT}"
echo "next (in order, or GitHub and the collector disagree and deliveries are lost):"
echo "  1. merge ${OUT} in a PR and wait for Argo CD to sync it"
echo "  2. kubectl -n ${NS} rollout restart deploy/github-actions-collector"
echo "  3. run the Repo Config Apply workflow (updates the GitHub webhook)"
echo "  4. redeliver any failed deliveries from the webhook's delivery log"
