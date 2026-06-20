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
# the calling sh_binary bakes the subcommand as $1. Bitwarden unlock is handled
# for you: if locked, the target prompts for the master password (or uses
# $BW_PASSWORD / a pre-set $BW_SESSION). You must `bw login` once beforehand.
set -euo pipefail

# NB: keep this :? message free of { } — a literal brace closes the ${...:?} early
# and the trailing brace would be appended to SUBCMD (e.g. "backup}" -> no case match).
SUBCMD="${1:?usage: sealed-secrets-backup | sealed-secrets-restore}"
shift || true

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"
NS="${SS_NAMESPACE:-sealed-secrets}"
LABEL="sealedsecrets.bitnami.com/sealed-secrets-key"
CONTROLLER="${SS_CONTROLLER:-sealed-secrets-controller}"
ITEM="${SS_BW_ITEM:-dev-local sealed-secrets controller keys}"
FILE="sealed-secrets-keys.json"

for t in kubectl bw jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "ERROR: '$t' not found on PATH." >&2; exit 1; }
done

# Ensure a usable Bitwarden session, folding `bw unlock` into the target (no
# manual export needed). Priority: existing unlocked $BW_SESSION -> $BW_PASSWORD
# (non-interactive) -> interactive master-password prompt (bazel run keeps the TTY).
ss_status() { bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo unknown; }
st="$(ss_status)"
if [ "$st" != "unlocked" ]; then
  if [ "$st" = "unauthenticated" ]; then
    echo "ERROR: not logged in to Bitwarden — run 'bw login' once, then re-run." >&2
    exit 1
  fi
  if [ -n "${BW_PASSWORD:-}" ]; then
    BW_SESSION="$(bw unlock --passwordenv BW_PASSWORD --raw)" \
      || { echo "ERROR: 'bw unlock' failed (BW_PASSWORD)." >&2; exit 1; }
  elif [ -t 0 ]; then
    echo "Unlocking Bitwarden — enter your master password:" >&2
    BW_SESSION="$(bw unlock --raw)" \
      || { echo "ERROR: 'bw unlock' failed." >&2; exit 1; }
  else
    echo "ERROR: Bitwarden is locked and there's no TTY to prompt. Either:" >&2
    echo "    export BW_SESSION=\$(bw unlock --raw)   # then re-run, or" >&2
    echo "    export BW_PASSWORD=...                  # for non-interactive unlock" >&2
    exit 1
  fi
  [ -n "${BW_SESSION:-}" ] || { echo "ERROR: 'bw unlock' returned an empty session." >&2; exit 1; }
  export BW_SESSION
fi

# The plaintext key only ever lives in this private temp dir; umask + the EXIT/signal
# trap keep it 0600 and ensure it's wiped on any normal or interrupted exit.
umask 077
tmpd="$(mktemp -d -t sskeys.XXXXXX)"
trap 'rm -rf "$tmpd"' EXIT INT TERM HUP
F="$tmpd/$FILE"

# Tolerant of a missing item: `bw get item` exits non-zero when the item is absent,
# which under `set -o pipefail` would otherwise abort this whole script at the bare
# `id="$(item_id)"` assignment (set -e) BEFORE the create / not-found branches run.
item_id() { bw get item "$ITEM" 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true; }

# Count the Secret objects in a captured List JSON (0 if the file is absent/empty).
key_count() { jq '[.items[]? | select(.kind == "Secret")] | length' "$1" 2>/dev/null || echo 0; }

case "$SUBCMD" in
  backup)
    # Capture as JSON and strip server-managed metadata so the artifact is create-clean:
    # a later restore can't hit a resourceVersion Conflict (which would also echo the
    # base64 tls.key to the console). The data/type/name/labels that the controller
    # needs are preserved.
    kubectl --context "$KCTX" -n "$NS" get secret -l "$LABEL" -o json \
      | jq 'del(.metadata.resourceVersion)
            | del(.items[].metadata.resourceVersion, .items[].metadata.uid,
                  .items[].metadata.creationTimestamp, .items[].metadata.generation,
                  .items[].metadata.managedFields,
                  .items[].metadata.annotations."kubectl.kubernetes.io/last-applied-configuration")' \
      > "$F"
    n="$(key_count "$F")"
    [ "$n" -ge 1 ] || { echo "ERROR: no sealed-secrets keys (label $LABEL) found in ns '$NS'." >&2; exit 1; }

    bw sync >/dev/null 2>&1 || true
    id="$(item_id)"
    if [ -z "$id" ]; then
      # `|| true`: keep a failed create pipeline (set -e / pipefail) from aborting
      # before the explicit empty-id check below can report it.
      id="$(jq -n --arg n "$ITEM" '{type:2,secureNote:{type:0},name:$n,notes:"Sealed-secrets controller private keys for dev-local — the ONLY thing that decrypts the SealedSecrets in git. Restore: bazel run //tools/gitops:sealed-secrets-restore"}' | bw encode | bw create item | jq -r '.id // empty' || true)"
      [ -n "$id" ] || { echo "ERROR: 'bw create item' failed or returned no id." >&2; exit 1; }
      echo "Created Bitwarden item: $ITEM"
    fi
    # Replace any prior copy of the attachment so re-running backup is idempotent.
    for att in $(bw get item "$id" 2>/dev/null | jq -r --arg f "$FILE" '.attachments[]? | select(.fileName == $f) | .id'); do
      bw delete attachment "$att" --itemid "$id" >/dev/null 2>&1 || true
    done
    bw create attachment --file "$F" --itemid "$id" >/dev/null \
      || { echo "ERROR: failed to upload the key attachment to Bitwarden." >&2; exit 1; }
    bw sync >/dev/null 2>&1 || true
    echo "✓ Backed up ${n} sealed-secrets key secret(s) to Bitwarden item '$ITEM' (attachment: $FILE)."
    ;;
  restore)
    bw sync >/dev/null 2>&1 || true
    id="$(item_id)"
    [ -n "$id" ] || { echo "ERROR: Bitwarden item '$ITEM' not found (nothing to restore)." >&2; exit 1; }
    bw get attachment "$FILE" --itemid "$id" --output "$F" >/dev/null 2>&1 \
      || { echo "ERROR: Bitwarden attachment '$FILE' not found on item '$ITEM' (backup incomplete?)." >&2; exit 1; }
    n="$(key_count "$F")"
    [ "$n" -ge 1 ] || { echo "ERROR: Bitwarden attachment '$FILE' is missing or invalid." >&2; exit 1; }

    echo "Applying ${n} sealed-secrets key(s) to ns '$NS' and restarting '$CONTROLLER'..."
    kubectl --context "$KCTX" -n "$NS" apply -f "$F"
    kubectl --context "$KCTX" -n "$NS" rollout restart deployment "$CONTROLLER"
    kubectl --context "$KCTX" -n "$NS" rollout status deployment "$CONTROLLER" --timeout=120s
    echo "✓ Restored ${n} sealed-secrets key(s); controller is up. Existing SealedSecrets will decrypt with the restored key."
    ;;
  *)
    echo "ERROR: unknown subcommand '$SUBCMD' (backup|restore)" >&2
    exit 2
    ;;
esac
