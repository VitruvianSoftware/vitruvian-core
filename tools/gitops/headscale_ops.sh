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
# Operational CLI wrapper for managing Headscale and generating API keys for
# Headplane (gitops/argocd/platform/headscale). Adheres to repo policy: no
# hand-run kubectl exec commands (§2.2 low-friction ops run behind bazel
# wrappers).
#
#   bazel run //tools/gitops:headscale -- <args...>
#   bazel run //tools/gitops:headscale-apikey-create [-- --expiration 90d]
#   bazel run //tools/gitops:headscale-apikey-list
#   bazel run //tools/gitops:headscale-apikey-expire -- --prefix <prefix>
#   bazel run //tools/gitops:headscale-user-create -- <username>
#   bazel run //tools/gitops:headscale-user-list
#   bazel run //tools/gitops:headscale-user-destroy -- <username>
#   bazel run //tools/gitops:headscale-node-list
#   bazel run //tools/gitops:headscale-node-register -- --user <username> --key <node-key>
#   bazel run //tools/gitops:headscale-node-delete -- <node-id>
#   bazel run //tools/gitops:headscale-preauthkey-create -- --user <username> [--reusable]
#   bazel run //tools/gitops:headscale-preauthkey-list -- --user <username>
set -euo pipefail

SUBCMD="${1:?usage: headscale-SUBCMD (raw|apikey-create|apikey-list|apikey-expire|user-create|user-list|user-destroy|node-list|node-register|node-delete|preauthkey-create|preauthkey-list)}"
shift || true

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"
NS=headscale

command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found on PATH." >&2; exit 1; }

POD="$(kubectl --context "$KCTX" -n "$NS" get pods -l app.kubernetes.io/name=headscale -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [ -z "$POD" ]; then
  echo "ERROR: no running headscale pod found in namespace '$NS' (kubectl get pods -n $NS -l app.kubernetes.io/name=headscale). Is the headscale Application synced?" >&2
  exit 1
fi

kexec() {
  kubectl --context "$KCTX" -n "$NS" exec -c headscale "$POD" -- headscale "$@"
}

case "$SUBCMD" in
  raw)
    kexec "$@"
    ;;
  apikey-create)
    kexec apikeys create "$@"
    ;;
  apikey-list)
    kexec apikeys list "$@"
    ;;
  apikey-expire)
    kexec apikeys expire "$@"
    ;;
  user-create)
    USER="${1:?usage: headscale-user-create USERNAME}"
    kexec users create "$USER"
    ;;
  user-list)
    kexec users list "$@"
    ;;
  user-destroy)
    USER="${1:?usage: headscale-user-destroy USERNAME}"
    kexec users destroy "$USER" "$@"
    ;;
  node-list)
    kexec nodes list "$@"
    ;;
  node-register)
    kexec nodes register "$@"
    ;;
  node-delete)
    NODE="${1:?usage: headscale-node-delete NODE_ID}"
    kexec nodes delete --identifier "$NODE"
    ;;
  preauthkey-create)
    kexec preauthkeys create "$@"
    ;;
  preauthkey-list)
    kexec preauthkeys list "$@"
    ;;
  *)
    echo "ERROR: unknown subcmd '$SUBCMD'" >&2
    exit 2
    ;;
esac
