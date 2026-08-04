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
# One low-friction operational step (§2.2 ops run through bazel wrappers): seal
# the ntfy alert-delivery endpoint that Alertmanager reads, so page/warning
# alerts push to your phone instead of being dropped. Wraps the whole
# kubectl-create-secret | kubeseal chain behind one arg — the ntfy topic URL.
#
#   bazel run //tools/gitops:seal-alert-ntfy -- 'https://ntfy.host/mytopic'
#   bazel run //tools/gitops:seal-alert-ntfy                       # prompts for the URL
#   bazel run //tools/gitops:seal-alert-ntfy -- 'https://…' --apply # also apply now
#
# Writes the SealedSecret to gitops/argocd/platform/sealed-secrets-manifests
# (commit it → ArgoCD applies, then Alertmanager mounts
# alertmanager-ntfy-endpoint/ntfy-url). NOT platform/prometheus: that
# Application's only source is the remote Helm chart (single-source, no
# directory.recurse of its own folder), so a loose file dropped there is
# never picked up by anything — confirmed live: the file sat in git for
# several minutes with no matching SealedSecret ever appearing in-cluster.
# sealed-secrets-manifests is the actual git-source Application for
# cross-namespace SealedSecrets (each carries its own metadata.namespace);
# every other SealedSecret in this repo already lives there. The URL is
# never printed. See gitops/argocd/platform/prometheus/applicationset.yaml
# (alertmanager.config) — the consuming receiver.
set -euo pipefail

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"

NS=monitoring
SECRET=alertmanager-ntfy-endpoint
KEY=ntfy-url
OUT="gitops/argocd/platform/sealed-secrets-manifests/${SECRET}.sealedsecret.yaml"
CTRL_NS="${SEALED_SECRETS_NAMESPACE:-sealed-secrets}"
CTRL_NAME="${SEALED_SECRETS_CONTROLLER:-sealed-secrets-controller}"

APPLY=0
URL=""
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    -*) echo "ERROR: unknown flag '$a' (expected the ntfy URL and/or --apply)" >&2; exit 2 ;;
    *) URL="$a" ;;
  esac
done

# Prefer the prompt so the URL doesn't land in shell history.
if [ -z "$URL" ]; then
  read -rp "ntfy topic URL (e.g. https://ntfy.host/mytopic): " URL
fi
case "$URL" in
  https://*|http://*) ;;
  *) echo "ERROR: expected an http(s) ntfy URL, got: '$URL'" >&2; exit 2 ;;
esac

for c in kubectl kubeseal; do
  command -v "$c" >/dev/null 2>&1 || { echo "ERROR: $c not found on PATH." >&2; exit 1; }
done

cd "${BUILD_WORKSPACE_DIRECTORY:?this target must be run via 'bazel run', not 'bazel build'}"

# create-secret (client dry-run) → kubeseal → committed SealedSecret. The URL is
# piped on stdin and never echoed.
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
printf '%s' "$URL" \
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
