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
# Back up / restore the sealed-secrets controller PRIVATE KEYS to/from Bitwarden.
# These keys are the ONLY thing that can decrypt the SealedSecrets committed to
# the (public) repo, so they must live off-cluster in a vault. Invoked via
# `bazel run //tools/gitops:sealed-secrets-backup` / `:sealed-secrets-restore`;
# the calling sh_binary bakes the subcommand as $1. Bitwarden auth comes from
# $BW_SESSION (run `export BW_SESSION=$(bw unlock --raw)` first). Never directly.
set -euo pipefail

SUBCMD="${1:?usage: sealed-secrets-{backup|restore}}"
shift || true

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"
NS="${SS_NAMESPACE:-sealed-secrets}"
LABEL="sealedsecrets.bitnami.com/sealed-secrets-key"
CONTROLLER="${SS_CONTROLLER:-sealed-secrets-controller}"
ITEM="${SS_BW_ITEM:-dev-local sealed-secrets controller keys}"
FILE="sealed-secrets-keys.yaml"

for t in kubectl bw jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "ERROR: '$t' not found on PATH." >&2; exit 1; }
done

# Bitwarden must be unlocked; the CLI reads $BW_SESSION automatically.
if [ "$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo unknown)" != "unlocked" ]; then
  echo "ERROR: Bitwarden CLI is not unlocked. Set up a session, then re-run:" >&2
  echo "    bw login                              # once, if not logged in" >&2
  echo "    export BW_SESSION=\$(bw unlock --raw)  # unlock; bazel run inherits the env" >&2
  exit 1
fi

tmpd="$(mktemp -d -t sskeys.XXXXXX)"
trap 'rm -rf "$tmpd"' EXIT
F="$tmpd/$FILE"

item_id() { bw get item "$ITEM" 2>/dev/null | jq -r '.id // empty' 2>/dev/null; }

case "$SUBCMD" in
  backup)
    kubectl --context "$KCTX" -n "$NS" get secret -l "$LABEL" -o yaml > "$F"
    grep -q "kind: Secret" "$F" || { echo "ERROR: no sealed-secrets keys (label $LABEL) found in ns '$NS'." >&2; exit 1; }
    n="$(grep -c "kind: Secret" "$F" || true)"
    bw sync >/dev/null 2>&1 || true
    id="$(item_id)"
    if [ -z "$id" ]; then
      id="$(jq -n --arg n "$ITEM" '{type:2,secureNote:{type:0},name:$n,notes:"Sealed-secrets controller private keys for dev-local — the ONLY thing that decrypts the SealedSecrets in git. Restore: bazel run //tools/gitops:sealed-secrets-restore"}' | bw encode | bw create item | jq -r '.id')"
      echo "Created Bitwarden item: $ITEM"
    fi
    # Replace any prior copy of the attachment so backups are idempotent.
    for att in $(bw get item "$id" | jq -r --arg f "$FILE" '.attachments[]? | select(.fileName==$f) | .id'); do
      bw delete attachment "$att" --itemid "$id" >/dev/null 2>&1 || true
    done
    bw create attachment --file "$F" --itemid "$id" >/dev/null
    bw sync >/dev/null 2>&1 || true
    echo "✓ Backed up ${n} sealed-secrets key secret(s) to Bitwarden item '$ITEM' (attachment: $FILE)."
    ;;
  restore)
    id="$(item_id)"
    [ -n "$id" ] || { echo "ERROR: Bitwarden item '$ITEM' not found (nothing to restore)." >&2; exit 1; }
    bw sync >/dev/null 2>&1 || true
    bw get attachment "$FILE" --itemid "$id" --output "$F" >/dev/null
    grep -q "kind: Secret" "$F" || { echo "ERROR: Bitwarden attachment '$FILE' is missing or invalid." >&2; exit 1; }
    echo "Applying sealed-secrets key(s) to ns '$NS' and restarting '$CONTROLLER'..."
    kubectl --context "$KCTX" -n "$NS" apply -f "$F"
    kubectl --context "$KCTX" -n "$NS" rollout restart deployment "$CONTROLLER"
    echo "✓ Restored sealed-secrets keys + restarted the controller. Existing SealedSecrets will decrypt with the restored key."
    ;;
  *)
    echo "ERROR: unknown subcommand '$SUBCMD' (backup|restore)" >&2
    exit 2
    ;;
esac
