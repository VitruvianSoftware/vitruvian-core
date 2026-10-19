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

# Seal the vitruvian-arc GitHub App's credentials for the merge-queue runners
# (Actions Runner Controller, gitops/argocd/platform/actions-runners).
#
#   bazel run //tools/gitops:seal-arc-github-app             # seal
#   bazel run //tools/gitops:seal-arc-github-app -- --apply  # also apply now
#
# The App id and installation id are public identifiers, so they are written
# here. The private key is read from the Bitwarden-backed store
# (tools/sync-env-secrets/agent-keys/vitruvian-arc.pem; on a new machine,
# `bazel run //tools/sync-env-secrets:agent-keys-pull` first). It must be mode
# 600 and a valid RSA key, or nothing is sealed.
#
# Writes gitops/argocd/platform/sealed-secrets-manifests/vitruvian-arc-github-app.sealedsecret.yaml:
# commit it and ArgoCD applies it; the scale set reads the Secret
# arc-runners/vitruvian-arc-github-app (githubConfigSecret).
# Spec: docs/superpowers/specs/2026-10-19-queue-runners-on-homelab-design.md
set -euo pipefail

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"

APP_ID="${ARC_APP_ID:-5387602}"
INSTALLATION_ID="${ARC_INSTALLATION_ID:-173186413}"
NS=arc-runners
SECRET=vitruvian-arc-github-app
CTRL_NS="${SEALED_SECRETS_NAMESPACE:-sealed-secrets}"
CTRL_NAME="${SEALED_SECRETS_CONTROLLER:-sealed-secrets-controller}"

APPLY=0
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    *) echo "ERROR: unknown argument '$a' (expected --apply or nothing)." >&2; exit 2 ;;
  esac
done

for c in kubectl kubeseal openssl; do
  command -v "$c" >/dev/null 2>&1 || { echo "ERROR: $c not found on PATH." >&2; exit 1; }
done

cd "${BUILD_WORKSPACE_DIRECTORY:?this target must be run via 'bazel run', not 'bazel build'}"

KEY="${ARC_APP_KEY:-tools/sync-env-secrets/agent-keys/vitruvian-arc.pem}"
OUT="gitops/argocd/platform/sealed-secrets-manifests/${SECRET}.sealedsecret.yaml"

[ -r "$KEY" ] || {
  echo "ERROR: no key at $KEY. Run 'bazel run //tools/sync-env-secrets:agent-keys-pull' (Bitwarden unlocked) first." >&2
  exit 1
}
# GNU stat first: on Linux `stat -f` means filesystem status and succeeds, so
# trying the BSD form first would never fall through. BSD stat rejects -c.
mode="$(stat -c '%a' "$KEY" 2>/dev/null || stat -f '%Lp' "$KEY")"
[ "$mode" = 600 ] || { echo "ERROR: $KEY is mode $mode; expected 600. Nothing was sealed." >&2; exit 1; }
openssl rsa -in "$KEY" -check -noout >/dev/null 2>&1 || {
  echo "ERROR: $KEY is not a valid RSA private key. Nothing was sealed." >&2
  exit 1
}

TMP_OUT="$(mktemp)"
trap 'rm -f "$TMP_OUT"' EXIT
# License header first: license-check requires it on every committed file, and
# kubeseal's output has none.
sed -n '2,20p' "${BASH_SOURCE[0]}" >"$TMP_OUT"
kubectl --context "$KCTX" create secret generic "$SECRET" -n "$NS" --dry-run=client -o yaml \
    --from-literal=github_app_id="$APP_ID" \
    --from-literal=github_app_installation_id="$INSTALLATION_ID" \
    --from-file=github_app_private_key="$KEY" \
  | kubeseal --context "$KCTX" --format yaml \
      --controller-namespace "$CTRL_NS" --controller-name "$CTRL_NAME" \
  >>"$TMP_OUT"
grep -q 'github_app_private_key:' "$TMP_OUT" || { echo "ERROR: kubeseal produced no sealed key. Nothing was written." >&2; exit 1; }
mv "$TMP_OUT" "$OUT"
trap - EXIT
echo "✓ sealed → $OUT (SealedSecret ${NS}/${SECRET}: App ${APP_ID}, installation ${INSTALLATION_ID})"

if [ "$APPLY" -eq 1 ]; then
  kubectl --context "$KCTX" apply -f "$OUT"
  echo "✓ applied: the sealed-secrets controller will materialize ${NS}/${SECRET}"
else
  echo "next: commit ${OUT} (ArgoCD applies it), or re-run with --apply to apply now"
fi
