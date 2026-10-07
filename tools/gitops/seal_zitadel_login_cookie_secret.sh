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
# Generate and seal the secret the Zitadel Login UI signs its session cookie
# with (ZITADEL_SESSION_COOKIE_SECRET, required form from Login UI v4.19.2:
# at least 32 characters, identical on every login replica).
#
# Without it the Login UI still works but derives the signing key from its API
# credential and logs a deprecation warning at every start; rotating that
# credential would then sign every user out. With it, the two are independent.
#
#   bazel run //tools/gitops:seal-zitadel-login-cookie-secret
#
# Writes the SealedSecret to gitops/argocd/platform/sealed-secrets-manifests.
# Commit it and Argo CD applies it; the zitadel ApplicationSet points the chart
# at it with login.sessionCookieSecretName. There is deliberately no --apply:
# this is the live identity provider, and it changes through git only.
#
# RE-RUNNING THIS ROTATES THE SECRET AND SIGNS EVERYONE OUT of the Login UI
# (application sessions and issued tokens are not affected). The value may be a
# comma-separated list -- the first entry signs, all are accepted -- so a
# rotation that keeps users signed in needs "new,old". This tool only ever
# writes a single fresh value; it cannot read the old one back.
set -euo pipefail

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"

NS=zitadel
SECRET=zitadel-login-session-cookie
KEY=ZITADEL_SESSION_COOKIE_SECRET
OUT="gitops/argocd/platform/sealed-secrets-manifests/${SECRET}.sealedsecret.yaml"
CTRL_NS="${SEALED_SECRETS_NAMESPACE:-sealed-secrets}"
CTRL_NAME="${SEALED_SECRETS_CONTROLLER:-sealed-secrets-controller}"

if [ "$#" -ne 0 ]; then
  echo "ERROR: this target takes no arguments (the secret is generated, never typed)." >&2
  exit 2
fi

for c in kubectl kubeseal openssl; do
  command -v "$c" >/dev/null 2>&1 || { echo "ERROR: $c not found on PATH." >&2; exit 1; }
done

cd "${BUILD_WORKSPACE_DIRECTORY:?this target must be run via 'bazel run', not 'bazel build'}"

# 48 random alphanumeric characters: comfortably over the 32-character minimum
# below which the Login UI reports not ready, and free of the comma that
# separates entries in a rotation list.
COOKIE_SECRET="$(openssl rand -base64 96 | tr -dc 'A-Za-z0-9' | head -c 48)"
if [ "${#COOKIE_SECRET}" -ne 48 ]; then
  echo "ERROR: failed to generate a 48-char secret (got ${#COOKIE_SECRET} chars)." >&2
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
  | kubeseal --context "$KCTX" --format yaml \
      --controller-namespace "$CTRL_NS" --controller-name "$CTRL_NAME" \
  >> "$OUT"

# A SealedSecret with an EMPTY payload still passes `kubeseal --validate`, which
# only proves the blob decrypts. Check the shape too: the one key is present and
# carries a real ciphertext.
if ! grep -qE "^[[:space:]]+${KEY}: Ag[A-Za-z0-9+/=]{200,}$" "$OUT"; then
  echo "ERROR: $OUT has no sealed value under ${KEY} -- do not commit it." >&2
  exit 1
fi
kubeseal --context "$KCTX" --validate \
    --controller-namespace "$CTRL_NS" --controller-name "$CTRL_NAME" < "$OUT"

echo "✓ sealed → $OUT (SealedSecret ${NS}/${SECRET}, key ${KEY})"
echo "next: commit ${OUT}; Argo CD applies it and the login pods roll"
