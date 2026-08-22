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
# One low-friction operational step: generate and seal the headplane session
# cookie_secret (a 32-char random string required by headplane 0.5.x).
# Wraps the openssl-rand | kubectl-create-secret | kubeseal chain behind
# one command with no arguments — the secret is generated, never typed.
#
#   bazel run //tools/gitops:seal-headplane-secret           # generate + seal
#   bazel run //tools/gitops:seal-headplane-secret -- --apply  # also apply now
#
# Writes the SealedSecret to gitops/argocd/platform/sealed-secrets-manifests
# (commit it → ArgoCD applies, then the headplane Deployment mounts
# headplane-secret/cookie-secret). Same pattern as seal-alert-ntfy.
set -euo pipefail

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"

NS=headscale
SECRET=headplane-secret
KEY=cookie-secret
OUT="gitops/argocd/platform/sealed-secrets-manifests/${SECRET}.sealedsecret.yaml"
CTRL_NS="${SEALED_SECRETS_NAMESPACE:-sealed-secrets}"
CTRL_NAME="${SEALED_SECRETS_CONTROLLER:-sealed-secrets-controller}"

APPLY=0
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    -*) echo "ERROR: unknown flag '$a' (expected --apply or nothing)." >&2; exit 2 ;;
    *) echo "ERROR: this target takes no positional arguments (the secret is auto-generated)." >&2; exit 2 ;;
  esac
done

for c in kubectl kubeseal openssl; do
  command -v "$c" >/dev/null 2>&1 || { echo "ERROR: $c not found on PATH." >&2; exit 1; }
done

cd "${BUILD_WORKSPACE_DIRECTORY:?this target must be run via 'bazel run', not 'bazel build'}"

# Generate a cryptographically random 32-char alphanumeric secret.
# headplane 0.5.x requires server.cookie_secret to be exactly 32 characters.
COOKIE_SECRET="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"
if [ "${#COOKIE_SECRET}" -ne 32 ]; then
  echo "ERROR: failed to generate a 32-char secret (got ${#COOKIE_SECRET} chars)." >&2
  exit 1
fi

# License header first: license-check (tools/license) requires it on every
# committed file, and kubeseal's raw output has none — without this, every
# re-seal (e.g. credential rotation) regenerates a file that fails CI.
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
HEADER
printf '%s' "$COOKIE_SECRET" \
  | kubectl --context "$KCTX" create secret generic "$SECRET" -n "$NS" \
      --dry-run=client --from-file="${KEY}=/dev/stdin" -o yaml \
  | kubeseal --format yaml \
      --controller-namespace "$CTRL_NS" --controller-name "$CTRL_NAME" \
  >> "$OUT"
echo "✓ sealed → $OUT (SealedSecret ${NS}/${SECRET}, key ${KEY})"

if [ "$APPLY" -eq 1 ]; then
  kubectl --context "$KCTX" apply -f "$OUT"
  echo "✓ applied — the sealed-secrets controller will materialize ${NS}/${SECRET}"
else
  echo "next: commit ${OUT} (ArgoCD applies it), or re-run with --apply to apply now"
fi
