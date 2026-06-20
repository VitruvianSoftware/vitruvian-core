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
# Generic GitOps/kubectl wrapper — invoked via `bazel run`, never directly.
# Mirrors //tools/pulumi: the calling sh_binary bakes the subcommand as $1
# (apply|delete|diff|status); anything after `--` is forwarded to kubectl.
# Operates on the real workspace tree ($BUILD_WORKSPACE_DIRECTORY), so manifest
# paths are workspace-relative. KUBECONFIG defaults to the dev-local cluster.
set -euo pipefail

SUBCMD="${1:?gitops subcommand required (apply|delete|diff|status)}"
shift || true

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl not found on PATH." >&2
  exit 1
fi

cd "${BUILD_WORKSPACE_DIRECTORY:?this target must be run via 'bazel run', not 'bazel build'}"

case "$SUBCMD" in
  apply)  exec kubectl --context "$KCTX" apply "$@" ;;
  delete) exec kubectl --context "$KCTX" delete "$@" ;;
  diff)   exec kubectl --context "$KCTX" diff "$@" ;;
  status)
    echo "=== ArgoCD projects / appsets / applications (sync · health) ==="
    exec kubectl --context "$KCTX" get appprojects,applicationsets,applications -n argocd -o wide "$@"
    ;;
  *) echo "ERROR: unknown gitops subcommand '$SUBCMD' (apply|delete|diff|status)" >&2; exit 2 ;;
esac
