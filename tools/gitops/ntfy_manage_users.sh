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
# General-purpose account lifecycle management for the self-hosted ntfy
# instance (gitops/argocd/platform/ntfy): list/add/delete users, rotate
# passwords, change roles, and grant/revoke per-topic access. This generalizes
# tools/gitops:ntfy-bootstrap-users (which still handles the one-time initial
# alertmanager+james provisioning) to any future account. Same class of
# operation as that script: ntfy's auth.db is a local SQLite file inside the
# pod, not something ArgoCD can own declaratively, so it gets the same
# bazel-wrapper treatment (§2.2 low-friction ops) instead of hand-run kubectl
# exec.
#
#   bazel run //tools/gitops:ntfy-user-list
#   bazel run //tools/gitops:ntfy-user-add -- USERNAME [admin|user]
#   bazel run //tools/gitops:ntfy-user-del -- USERNAME
#   bazel run //tools/gitops:ntfy-user-change-pass -- USERNAME
#   bazel run //tools/gitops:ntfy-user-change-role -- USERNAME admin|user
#   bazel run //tools/gitops:ntfy-user-access -- USERNAME TOPIC PERMISSION
#     (PERMISSION: read-write|read-only|write-only|deny)
#
# add/change-pass generate the password locally (openssl rand), send it only
# to stdin of the ntfy pod, and print it to stdout exactly once — save it to a
# password manager immediately. ntfy stores only the bcrypt hash, so a lost
# password means a re-rotate, not a recovery. Set NTFY_PASSWORD yourself
# beforehand to skip generation (e.g. for scripted, non-interactive re-runs).
set -euo pipefail

SUBCMD="${1:?usage: ntfy-user-SUBCMD (list|add|del|change-pass|change-role|access)}"
shift || true

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"
NS=ntfy

command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found on PATH." >&2; exit 1; }

POD="$(kubectl --context "$KCTX" -n "$NS" get pods -l app=ntfy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [ -z "$POD" ]; then
  echo "ERROR: no running ntfy pod found in namespace '$NS' (kubectl get pods -n $NS -l app=ntfy). Is the ntfy Application synced?" >&2
  exit 1
fi

kexec() { kubectl --context "$KCTX" -n "$NS" exec "$POD" -- "$@"; }
kexeci() { kubectl --context "$KCTX" -n "$NS" exec -i "$POD" -- "$@"; }

require_role() {
  case "$1" in
    admin|user) ;;
    *) echo "ERROR: role must be 'admin' or 'user', got '$1'" >&2; exit 2 ;;
  esac
}

gen_pass() { openssl rand -base64 24 | tr -d '\n=+/' | cut -c1-32; }

case "$SUBCMD" in
  list)
    kexec ntfy user list
    ;;
  add)
    USER="${1:?usage: ntfy-user-add USERNAME [admin|user]}"
    ROLE="${2:-user}"
    require_role "$ROLE"
    command -v openssl >/dev/null 2>&1 || { echo "ERROR: openssl not found on PATH." >&2; exit 1; }
    PASS="${NTFY_PASSWORD:-$(gen_pass)}"
    printf '%s\n%s\n' "$PASS" "$PASS" | kexeci ntfy user add "--role=${ROLE}" "$USER"
    echo "✓ created '$USER' (role: $ROLE)" >&2
    if [ -z "${NTFY_PASSWORD:-}" ]; then
      echo "password (save now, unrecoverable after this): $PASS"
    fi
    echo "next: grant topic access — bazel run //tools/gitops:ntfy-user-access -- $USER TOPIC read-only" >&2
    ;;
  del)
    USER="${1:?usage: ntfy-user-del USERNAME}"
    kexec ntfy user del "$USER"
    echo "✓ deleted '$USER'" >&2
    ;;
  change-pass)
    USER="${1:?usage: ntfy-user-change-pass USERNAME}"
    command -v openssl >/dev/null 2>&1 || { echo "ERROR: openssl not found on PATH." >&2; exit 1; }
    PASS="${NTFY_PASSWORD:-$(gen_pass)}"
    printf '%s\n%s\n' "$PASS" "$PASS" | kexeci ntfy user change-pass "$USER"
    echo "✓ rotated password for '$USER'" >&2
    if [ -z "${NTFY_PASSWORD:-}" ]; then
      echo "new password (save now, unrecoverable after this): $PASS"
    fi
    ;;
  change-role)
    USER="${1:?usage: ntfy-user-change-role USERNAME admin|user}"
    ROLE="${2:?usage: ntfy-user-change-role USERNAME admin|user}"
    require_role "$ROLE"
    kexec ntfy user change-role "$USER" "$ROLE"
    echo "✓ changed role for '$USER' to '$ROLE'" >&2
    ;;
  access)
    USER="${1:?usage: ntfy-user-access USERNAME TOPIC PERMISSION}"
    TOPIC="${2:?usage: ntfy-user-access USERNAME TOPIC PERMISSION}"
    PERM="${3:?usage: ntfy-user-access USERNAME TOPIC PERMISSION (read-write|read-only|write-only|deny)}"
    kexec ntfy access "$USER" "$TOPIC" "$PERM"
    echo "✓ set '$USER' access to '$TOPIC': $PERM" >&2
    ;;
  *)
    echo "ERROR: unknown subcommand '$SUBCMD' (list|add|del|change-pass|change-role|access)" >&2
    exit 2
    ;;
esac
