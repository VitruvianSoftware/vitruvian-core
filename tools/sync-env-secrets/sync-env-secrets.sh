#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# sync-env-secrets — manage deploy-time GitHub Actions secrets that do NOT live
# in GCP Secret Manager, as code, from a gitignored local store synced via
# Bitwarden. This is the sanctioned mechanism for that secret class under
# docs/engineering/application-development-principles.md §2.18 (every change ships
# as code) and §2.4 (secrets never live in git) — replacing ad-hoc `gh secret
# set`.
#
# Why a tool and not Pulumi (repo_config): repo_config CAN manage a GitHub secret
# in Pulumi — dependabotSecrets does, via a committed `secure:`-encrypted config
# value that the Pulumi Cloud backend decrypts in both local and CI applies. We
# deliberately keep these secrets out of that path:
#   - committing the value, EVEN Pulumi-encrypted, is a secret in git history
#     forever — what §2.4 forbids (that BUILDBUDDY_API_KEY line is the doc's own
#     acknowledged "(target)" debt, not a model to copy);
#   - the env-injected alternative (read from $ENV, nothing committed) would
#     flip-flop: a local apply sets the secret, then the next CI apply — lacking
#     the value — DELETES it from the shared Pulumi state;
#   - a multiline RSA/JSON machine key is awkward as a Pulumi config secret anyway.
# So the raw bytes live in a gitignored, Bitwarden-backed store — out of git
# entirely — and this idempotent tool PUTs them into GitHub. The non-secret
# environment VARIABLES it pairs with ARE in repo_config (oauthEnvironment).
#
# Store layout (gitignored; see secrets.example/ for the shape). One file per
# secret so arbitrary values (JSON blobs, multiline keys) round-trip verbatim:
#
#   tools/sync-env-secrets/secrets/<github-environment>/<SECRET_NAME>   # raw value
#
# Usage:
#   sync-env-secrets.sh apply   <github-environment>   # local store -> GitHub env secrets
#   sync-env-secrets.sh bw-pull                         # Bitwarden -> local store
#   sync-env-secrets.sh bw-push                         # local store -> Bitwarden
#
# Env overrides: REPO (default VitruvianSoftware/vitruvian-core), BW_ITEM.
# Bitwarden ops need an unlocked session: export BW_SESSION="$(bw unlock --raw)".
set -euo pipefail

REPO="${REPO:-VitruvianSoftware/vitruvian-core}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STORE="$HERE/secrets"
BW_ITEM="${BW_ITEM:-vitruvian-core/deploy-env-secrets}"
ARCHIVE_NAME="deploy-env-secrets.tar.gz"

# Any temp dir holding plaintext secrets is registered here and removed on ANY
# exit (including an errexit mid-sync), so a failed bw op never leaves the
# decrypted tarball behind in /tmp.
_tmp_cleanup=""
trap '[ -n "$_tmp_cleanup" ] && rm -rf "$_tmp_cleanup"' EXIT

die() { echo "error: $*" >&2; exit 1; }

cmd_apply() {
  local env="${1:-}"
  [ -n "$env" ] || die "usage: apply <github-environment>"
  local dir="$STORE/$env"
  [ -d "$dir" ] || die "no local store at $dir — run 'bw-pull' first (or copy from secrets.example/)"
  command -v gh >/dev/null || die "gh not installed"
  local count=0 f key
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    key="$(basename "$f")"
    case "$key" in .* | *.md) continue ;; esac
    # Value is piped from the file on stdin and is never printed.
    gh secret set "$key" --env "$env" --repo "$REPO" <"$f"
    echo "  set $key  (env=$env)"
    count=$((count + 1))
  done
  [ "$count" -gt 0 ] || die "no secret files found in $dir"
  echo "synced $count secret(s) to environment '$env' on $REPO"
}

require_bw() {
  command -v bw >/dev/null || die "bw (Bitwarden CLI) not installed: brew install bitwarden-cli"
  command -v jq >/dev/null || die "jq not installed"
  [ -n "${BW_SESSION:-}" ] || die "vault locked — run: export BW_SESSION=\"\$(bw unlock --raw)\""
}

bw_item_id() { bw list items --search "$BW_ITEM" | jq -r '.[0].id // empty'; }

cmd_bw_push() {
  require_bw
  [ -d "$STORE" ] || die "nothing to push: $STORE does not exist"
  bw sync >/dev/null
  local tmpdir tar id att_old
  tmpdir="$(mktemp -d)"
  _tmp_cleanup="$tmpdir"
  tar="$tmpdir/$ARCHIVE_NAME"
  tar -czf "$tar" -C "$STORE" .
  id="$(bw_item_id)"
  if [ -z "$id" ]; then
    id="$(printf '{"type":2,"name":"%s","notes":"gitignored deploy-time env secrets (managed by tools/sync-env-secrets)","secureNote":{"type":0}}' "$BW_ITEM" | bw encode | bw create item | jq -r '.id')"
    echo "  created Bitwarden item '$BW_ITEM' ($id)"
  else
    att_old="$(bw get item "$id" | jq -r --arg n "$ARCHIVE_NAME" '.attachments[]? | select(.fileName==$n) | .id')"
    [ -z "$att_old" ] || bw delete attachment "$att_old" --itemid "$id" >/dev/null
  fi
  bw create attachment --itemid "$id" --file "$tar" >/dev/null
  echo "pushed $ARCHIVE_NAME to Bitwarden item '$BW_ITEM'"
}

cmd_bw_pull() {
  require_bw
  bw sync >/dev/null
  local id att tmpdir tar
  id="$(bw_item_id)"
  [ -n "$id" ] || die "no Bitwarden item '$BW_ITEM' — run 'bw-push' first"
  att="$(bw get item "$id" | jq -r --arg n "$ARCHIVE_NAME" '.attachments[]? | select(.fileName==$n) | .id')"
  [ -n "$att" ] || die "no '$ARCHIVE_NAME' attachment on item '$BW_ITEM'"
  tmpdir="$(mktemp -d)"
  _tmp_cleanup="$tmpdir"
  tar="$tmpdir/$ARCHIVE_NAME"
  bw get attachment "$att" --itemid "$id" --output "$tar" >/dev/null
  mkdir -p "$STORE"
  tar -xzf "$tar" -C "$STORE"
  echo "pulled store from Bitwarden item '$BW_ITEM' into $STORE"
}

case "${1:-}" in
  apply)
    shift
    cmd_apply "$@"
    ;;
  bw-push)
    shift
    cmd_bw_push "$@"
    ;;
  bw-pull)
    shift
    cmd_bw_pull "$@"
    ;;
  *)
    cat >&2 <<EOF
sync-env-secrets — manage non-GCP-SM deploy secrets as code (§2.18)

usage:
  $(basename "$0") apply   <github-environment>   # local store -> GitHub env secrets
  $(basename "$0") bw-pull                         # Bitwarden -> local store
  $(basename "$0") bw-push                         # local store -> Bitwarden

store: $STORE/<github-environment>/<SECRET_NAME>   (gitignored; see secrets.example/)
EOF
    exit 2
    ;;
esac
