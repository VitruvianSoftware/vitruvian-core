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
#   bazel run //tools/gitops:ntfy-user-change-pass -- USERNAME --gh-secret NAME
#   bazel run //tools/gitops:ntfy-rotate-ci-password   (= github-actions -> NTFY_GITHUB_ACTIONS_PASSWORD)
#   bazel run //tools/gitops:ntfy-user-change-role -- USERNAME admin|user
#   bazel run //tools/gitops:ntfy-user-access -- USERNAME TOPIC PERMISSION
#     (PERMISSION: read-write|read-only|write-only|deny)
#
# add/change-pass generate the password locally (openssl rand), send it only
# to stdin of the ntfy pod, and print it to stdout exactly once — save it to a
# password manager immediately. ntfy stores only the bcrypt hash, so a lost
# password means a re-rotate, not a recovery. Set NTFY_PASSWORD yourself
# beforehand to skip generation (e.g. for scripted, non-interactive re-runs).
#
# change-pass --gh-secret NAME is for accounts a GitHub workflow logs in with:
# the new password goes to the pod AND to the repo secret NAME (both over
# stdin), is checked against the live server, and is NEVER printed -- no human
# needs to hold it. Re-run to rotate again.
set -euo pipefail

SUBCMD="${1:?usage: ntfy-user-SUBCMD (list|add|del|change-pass|change-role|access)}"
shift || true

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"
NS=ntfy
NTFY_URL="${NTFY_URL:-https://ntfy.ipv1337.dev}"
GH_REPO="${GH_REPO:-VitruvianSoftware/vitruvian-core}"

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

# 48 random bytes -> 64 base64 chars; dropping =+/ still leaves well over 32.
gen_pass() { openssl rand -base64 48 | tr -d '\n=+/' | cut -c1-32; }

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
    USER="${1:?usage: ntfy-user-change-pass USERNAME [--gh-secret NAME]}"
    GH_SECRET=""
    if [ "${2:-}" = "--gh-secret" ]; then
      GH_SECRET="${3:?usage: ntfy-user-change-pass USERNAME --gh-secret NAME}"
      for tool in gh curl; do
        command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool not found on PATH." >&2; exit 1; }
      done
      gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not signed in -- run 'gh auth login'." >&2; exit 1; }
      # Fail BEFORE touching the password if the account isn't there: a
      # change-pass on a missing user would leave the secret and the pod apart.
      kexec ntfy user list 2>&1 | grep -qE "^user ${USER} " \
        || { echo "ERROR: no ntfy user '${USER}' -- create it first (ntfy-user-add)." >&2; exit 1; }
    fi
    command -v openssl >/dev/null 2>&1 || { echo "ERROR: openssl not found on PATH." >&2; exit 1; }
    PASS="${NTFY_PASSWORD:-$(gen_pass)}"
    printf '%s\n%s\n' "$PASS" "$PASS" | kexeci ntfy user change-pass "$USER"
    echo "✓ rotated password for '$USER'" >&2
    if [ -n "$GH_SECRET" ]; then
      # From here the pod has the new password and CI still has the old one,
      # so store it straight away. If this fails, just re-run: it rotates again.
      printf '%s' "$PASS" | gh secret set "$GH_SECRET" --repo "$GH_REPO" >/dev/null \
        || { echo "ERROR: could not store $GH_SECRET -- CI can't log in to ntfy until you re-run this." >&2; exit 1; }
      echo "✓ stored it as the $GH_REPO secret $GH_SECRET (never printed)" >&2
      # Prove the new password works on the live server. The credentials go
      # to curl on stdin, never on its command line.
      if printf 'user = "%s:%s"\n' "$USER" "$PASS" | curl -fsS -o /dev/null --config - "${NTFY_URL}/v1/account"; then
        echo "✓ ${NTFY_URL} accepts the new password" >&2
      else
        echo "ERROR: ${NTFY_URL} rejected the new password -- re-run to rotate again." >&2
        exit 1
      fi
      unset PASS
    elif [ -z "${NTFY_PASSWORD:-}" ]; then
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
