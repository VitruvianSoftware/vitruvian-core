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
# Back up / restore the ArgoCD `argocd-secret` to/from Bitwarden. Unlike the
# SealedSecrets (which the controller can re-materialize from git), ArgoCD is the
# pulumi bootstrap and comes up BEFORE the (ArgoCD-managed) sealed-secrets
# controller — so argocd-secret cannot itself be a SealedSecret. It carries the
# `server.secretkey` (the signing key for API tokens) and `accounts.mcp.tokens`
# (the token-id seed). Backing it up to a vault means a cluster reinstall can
# restore the SAME signing key + token seed, so the existing MCP JWT keeps
# validating without re-minting. Invoked via
# `bazel run //tools/gitops:argocd-secret-{backup|restore|verify}`; the calling
# sh_binary bakes the subcommand as $1. Bitwarden unlock is automatic (prompts for
# the master password if locked, or uses $BW_PASSWORD / $BW_SESSION). `bw login`
# once beforehand. Requires kubectl, bw, jq, python3.
set -euo pipefail

SUBCMD="${1:?usage: argocd-secret-{backup|restore|verify}}"
shift || true

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"
NS="${ARGOCD_NAMESPACE:-argocd}"
SECRET="argocd-secret"
SERVER_DEPLOY="${ARGOCD_SERVER_DEPLOY:-argocd-server}"
ITEM="${ARGOCD_BW_ITEM:-dev-local argocd-secret (server.secretkey + mcp token)}"
FILE="argocd-secret.yaml"

for t in kubectl bw jq python3; do
  command -v "$t" >/dev/null 2>&1 || { echo "ERROR: '$t' not found on PATH." >&2; exit 1; }
done

# Ensure a usable Bitwarden session (same contract as sealed_secrets_keys.sh):
# existing unlocked $BW_SESSION -> $BW_PASSWORD (non-interactive) -> interactive prompt.
ss_status() { bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo unknown; }
if [ "$(ss_status)" != "unlocked" ]; then
  if [ "$(ss_status)" = "unauthenticated" ]; then
    echo "ERROR: not logged in to Bitwarden — run 'bw login' once, then re-run." >&2
    exit 1
  fi
  if [ -n "${BW_PASSWORD:-}" ]; then
    BW_SESSION="$(bw unlock --passwordenv BW_PASSWORD --raw)" \
      || { echo "ERROR: 'bw unlock' failed (BW_PASSWORD)." >&2; exit 1; }
  elif [ -t 0 ]; then
    echo "Unlocking Bitwarden — enter your master password:" >&2
    BW_SESSION="$(bw unlock --raw)" || { echo "ERROR: 'bw unlock' failed." >&2; exit 1; }
  else
    echo "ERROR: Bitwarden is locked and there's no TTY to prompt. Either:" >&2
    echo "    export BW_SESSION=\$(bw unlock --raw)   # then re-run, or" >&2
    echo "    export BW_PASSWORD=...                  # for non-interactive unlock" >&2
    exit 1
  fi
  export BW_SESSION
fi

tmpd="$(mktemp -d -t argocdsec.XXXXXX)"
trap 'rm -rf "$tmpd"' EXIT
F="$tmpd/$FILE"

item_id() { bw get item "$ITEM" 2>/dev/null | jq -r '.id // empty' 2>/dev/null; }

# Strip cluster-volatile metadata so `kubectl apply` of the backup works cleanly
# against a freshly chart-created argocd-secret on a reinstalled cluster.
strip_metadata() {
  python3 - "$1" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
m = d.get("metadata", {})
for k in ("resourceVersion", "uid", "creationTimestamp", "managedFields",
          "ownerReferences", "generation", "selfLink"):
    m.pop(k, None)
ann = m.get("annotations", {})
ann.pop("kubectl.kubernetes.io/last-applied-configuration", None)
if ann == {}:
    m.pop("annotations", None)
d.pop("status", None)
yaml.safe_dump(d, open(sys.argv[1], "w"), default_flow_style=False)
PY
}

case "$SUBCMD" in
  backup)
    kubectl --context "$KCTX" -n "$NS" get secret "$SECRET" -o yaml > "$F"
    grep -q "kind: Secret" "$F" || { echo "ERROR: $SECRET not found in ns '$NS'." >&2; exit 1; }
    grep -q "server.secretkey" "$F" || { echo "ERROR: $SECRET has no server.secretkey." >&2; exit 1; }
    strip_metadata "$F"
    bw sync >/dev/null 2>&1 || true
    id="$(item_id)"
    if [ -z "$id" ]; then
      id="$(jq -n --arg n "$ITEM" '{type:2,secureNote:{type:0},name:$n,notes:"ArgoCD argocd-secret (server.secretkey + accounts.mcp.tokens) for dev-local. Restore after a cluster reinstall so the existing MCP token keeps validating: bazel run //tools/gitops:argocd-secret-restore"}' | bw encode | bw create item | jq -r '.id')"
      echo "Created Bitwarden item: $ITEM"
    fi
    # Replace any prior copy so backups are idempotent.
    for att in $(bw get item "$id" | jq -r --arg f "$FILE" '.attachments[]? | select(.fileName==$f) | .id'); do
      bw delete attachment "$att" --itemid "$id" >/dev/null 2>&1 || true
    done
    bw create attachment --file "$F" --itemid "$id" >/dev/null
    bw sync >/dev/null 2>&1 || true
    echo "✓ Backed up $SECRET to Bitwarden item '$ITEM' (attachment: $FILE)."
    ;;
  restore)
    id="$(item_id)"
    [ -n "$id" ] || { echo "ERROR: Bitwarden item '$ITEM' not found (nothing to restore)." >&2; exit 1; }
    bw sync >/dev/null 2>&1 || true
    bw get attachment "$FILE" --itemid "$id" --output "$F" >/dev/null
    grep -q "server.secretkey" "$F" || { echo "ERROR: attachment '$FILE' is missing or invalid." >&2; exit 1; }
    echo "Applying $SECRET to ns '$NS' and restarting '$SERVER_DEPLOY'..."
    kubectl --context "$KCTX" -n "$NS" apply -f "$F"
    kubectl --context "$KCTX" -n "$NS" rollout restart deployment "$SERVER_DEPLOY"
    echo "✓ Restored $SECRET + restarted $SERVER_DEPLOY. The existing MCP JWT will validate."
    ;;
  verify)
    # Read-only: prove the backup is real (decodable + holds the required keys). No cluster access.
    bw sync >/dev/null 2>&1 || true
    id="$(item_id)"
    [ -n "$id" ] || { echo "✗ No Bitwarden item '$ITEM' found — nothing is backed up." >&2; exit 1; }
    bw get attachment "$FILE" --itemid "$id" --output "$F" >/dev/null 2>&1 \
      || { echo "✗ Item '$ITEM' exists but has NO '$FILE' attachment (re-run backup)." >&2; exit 1; }
    if grep -q "server.secretkey" "$F" && grep -q "accounts.mcp.tokens" "$F"; then
      echo "✓ Backup OK: item '$ITEM' holds '$FILE' with server.secretkey + accounts.mcp.tokens — restorable via 'bazel run //tools/gitops:argocd-secret-restore'."
    else
      echo "✗ Attachment '$FILE' present but missing server.secretkey and/or accounts.mcp.tokens." >&2
      exit 1
    fi
    ;;
  *)
    echo "ERROR: unknown subcommand '$SUBCMD' (backup|restore|verify)" >&2
    exit 2
    ;;
esac
