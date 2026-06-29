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
# Cluster/node lifecycle wrapper — kubectl behind bazel, for live-cluster
# operations NOT covered by //tools/gitops (which is ArgoCD-manifest oriented).
# Sibling of //tools/pulumi and //tools/gitops: the calling sh_binary bakes the
# operation as $1; anything after `--` is forwarded to kubectl. Invoke via
# `bazel run //tools/cluster:<op> -- <args>`, never directly. KUBECONFIG defaults
# to the dev-local cluster; context defaults to "default".
#
# Examples:
#   bazel run //tools/cluster:kubectl      -- get nodes -o wide
#   bazel run //tools/cluster:cordon       -- nuc9
#   bazel run //tools/cluster:drain        -- nuc9 --timeout=5m
#   bazel run //tools/cluster:delete-node  -- nuc9
#   bazel run //tools/cluster:label-node   -- nuc9i5 node.ipv1337.dev/link=wired --overwrite
#   # read-only HA/balance diagnostics (the node-balance / replica-spread audits):
#   bazel run //tools/cluster:balance                 # pods-per-node distribution
#   bazel run //tools/cluster:placement    -- -n monitoring -l app.kubernetes.io/name=alertmanager
#   bazel run //tools/cluster:minio-status            # drive/heal health + PV-node pinning
set -euo pipefail

OP="${1:?cluster op required (kubectl|cordon|uncordon|drain|delete-node|label-node|balance|placement|minio-status)}"
shift || true

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl not found on PATH." >&2
  exit 1
fi

# Operate from the real workspace tree so any manifest paths are workspace-relative.
cd "${BUILD_WORKSPACE_DIRECTORY:?this target must be run via 'bazel run', not 'bazel build'}"

case "$OP" in
  # General passthrough for any kubectl verb the named ops below don't cover
  # (wait, exec, get, delete pod/pvc, patch, ...).
  kubectl)     exec kubectl --context "$KCTX" "$@" ;;
  # Node lifecycle.
  cordon)      exec kubectl --context "$KCTX" cordon "$@" ;;
  uncordon)    exec kubectl --context "$KCTX" uncordon "$@" ;;
  # Safe drain defaults; forward extra flags (e.g. --force, --timeout=5m).
  drain)       exec kubectl --context "$KCTX" drain --ignore-daemonsets --delete-emptydir-data "$@" ;;
  delete-node) exec kubectl --context "$KCTX" delete node "$@" ;;
  label-node)  exec kubectl --context "$KCTX" label node "$@" ;;

  # Read-only diagnostics — the node-balance / HA-spread audits, behind bazel.
  # Pods-per-node distribution (Running only): how balanced the cluster is. Counts
  # by .spec.nodeName directly (NOT positional `-o wide` parsing — the RESTARTS
  # column can contain spaces like "1 (108m ago)" and shift the fields).
  balance)
    kubectl --context "$KCTX" get pods -A --field-selector=status.phase=Running \
      --no-headers -o 'custom-columns=NODE:.spec.nodeName' \
      | sort | uniq -c | sort -rn ;;
  # Which node each matching pod runs on — the HA spot-check ("are my replicas on
  # different nodes?"). Forward any selectors (-n, -l, --all-namespaces, ...).
  placement)
    exec kubectl --context "$KCTX" get pods \
      -o 'custom-columns=POD:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName' "$@" ;;
  # MinIO distributed-store health: pod placement, the node each drive's local-path
  # PV is pinned to (local-path can't migrate — a wrong pin strands a drive), and
  # mc network/drive/heal status. Namespace via MINIO_NS (default: minio).
  minio-status)
    ns="${MINIO_NS:-minio}"
    echo "== pods =="
    kubectl --context "$KCTX" -n "$ns" get pods -o wide
    echo; echo "== drive PV node pinning (local-path is node-bound) =="
    kubectl --context "$KCTX" get pv \
      -o 'custom-columns=PV:.metadata.name,CLAIM:.spec.claimRef.name,NS:.spec.claimRef.namespace,PINNED_NODE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]' \
      | awk -v ns="$ns" 'NR==1 || $3==ns'
    echo; echo "== mc admin info (network/drive/heal) =="
    pod="$(kubectl --context "$KCTX" -n "$ns" get pods -o name 2>/dev/null | grep -m1 . || true)"
    if [ -n "$pod" ]; then
      kubectl --context "$KCTX" -n "$ns" exec "${pod#pod/}" -- \
        sh -c 'mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1 && mc admin info local' \
        || echo "(mc admin info unavailable — pod not ready, or root creds not in env)"
    else
      echo "(no pods in namespace '$ns')"
    fi ;;

  *) echo "ERROR: unknown cluster op '$OP' (kubectl|cordon|uncordon|drain|delete-node|label-node|balance|placement|minio-status)" >&2; exit 2 ;;
esac
