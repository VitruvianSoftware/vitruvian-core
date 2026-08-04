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
# One-time bootstrap for the self-hosted ntfy instance (gitops/argocd/platform/ntfy):
# creates the two users ntfy's own auth.db needs before anything can publish/
# subscribe (server.yml sets auth-default-access: deny-all, since the server is
# public at ntfy.ipv1337.dev). This is imperative state inside ntfy's SQLite
# auth.db, not something gitops can own declaratively — same class of operation
# as the sealed-secrets-backup/restore and argocd-secret-* targets in this BUILD
# file, so it gets the same bazel-wrapper treatment (§2.2 low-friction ops)
# instead of a hand-run kubectl exec.
#
#   bazel run //tools/gitops:ntfy-bootstrap-users -- vitruvian-alerts
#   bazel run //tools/gitops:ntfy-bootstrap-users            # prompts for the topic name
#
# Creates:
#   - user "alertmanager", write-only on the topic — feed the printed password
#     straight into `bazel run //tools/gitops:seal-alert-ntfy -- '<password>'`.
#     The topic name here must match the url in the ntfy receiver config
#     (gitops/argocd/platform/prometheus/applicationset.yaml — currently
#     ntfy.ipv1337.dev/vitruvian-alerts, plain non-secret config since only
#     the password is sealed, see that file's comment for why); this script
#     doesn't write that file for you.
#   - user "james", read-only on the topic — for the ntfy phone app / web UI
# Both passwords are generated locally (openssl rand), never sent anywhere but
# stdin of the ntfy pod, and printed to your terminal exactly once — save them
# to a password manager immediately, they are not recoverable after this runs
# (ntfy stores only the bcrypt hash). Re-running is safe: existing users are
# skipped, not recreated (use `ntfy user change-pass` in-pod to rotate).
set -euo pipefail

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"
NS=ntfy

TOPIC="${1:-}"
if [ -z "$TOPIC" ]; then
  read -rp "ntfy topic name (e.g. vitruvian-alerts): " TOPIC
fi
case "$TOPIC" in
  ""|*[!a-zA-Z0-9_-]*) echo "ERROR: topic must be non-empty and match [a-zA-Z0-9_-]+, got: '$TOPIC'" >&2; exit 2 ;;
esac

for c in kubectl openssl; do
  command -v "$c" >/dev/null 2>&1 || { echo "ERROR: $c not found on PATH." >&2; exit 1; }
done

POD="$(kubectl --context "$KCTX" -n "$NS" get pods -l app=ntfy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [ -z "$POD" ]; then
  echo "ERROR: no running ntfy pod found in namespace '$NS' (kubectl get pods -n $NS -l app=ntfy). Is the ntfy Application synced?" >&2
  exit 1
fi

existing_users="$(kubectl --context "$KCTX" -n "$NS" exec "$POD" -- ntfy user list 2>/dev/null || true)"

# Prints progress to stderr; prints ONLY "user:pass" to stdout, and only when
# a new user was actually created (nothing on stdout when skipped) — so
# callers can safely capture just the credential via command substitution.
create_user() {
  local user="$1" access="$2"
  if printf '%s' "$existing_users" | grep -q "\\b${user}\\b"; then
    echo "= user '$user' already exists, skipping creation (rotate via: kubectl -n $NS exec -it $POD -- ntfy user change-pass $user)" >&2
    return 0
  fi
  local pass
  pass="$(openssl rand -base64 24 | tr -d '\n=+/' | cut -c1-32)"
  printf '%s\n%s\n' "$pass" "$pass" \
    | kubectl --context "$KCTX" -n "$NS" exec -i "$POD" -- ntfy user add --role=user "$user" >&2
  kubectl --context "$KCTX" -n "$NS" exec "$POD" -- ntfy access "$user" "$TOPIC" "$access" >&2
  echo "✓ created '$user' ($access on '$TOPIC')" >&2
  printf '%s:%s\n' "$user" "$pass"
}

echo "Bootstrapping ntfy users for topic '$TOPIC' (pod $POD)..." >&2
AM_CRED="$(create_user alertmanager write-only)"
JAMES_CRED="$(create_user james read-only)"

echo >&2
echo "Alertmanager webhook password (feed straight into seal-alert-ntfy, never commit it raw):" >&2
if [ -n "${AM_CRED:-}" ]; then
  AM_PASS="${AM_CRED#*:}"
  echo "  bazel run //tools/gitops:seal-alert-ntfy -- '${AM_PASS}'" >&2
else
  echo "  (user already existed — rotate its password first if you need it again)" >&2
fi
echo >&2
echo "James's ntfy app / web UI login (save to a password manager now):" >&2
if [ -n "${JAMES_CRED:-}" ]; then
  echo "  server: https://ntfy.ipv1337.dev   topic: ${TOPIC}   ${JAMES_CRED}" >&2
else
  echo "  (user already existed — rotate its password if you need it again)" >&2
fi
