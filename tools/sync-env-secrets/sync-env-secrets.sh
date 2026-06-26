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
# Usage (via bazel — preferred; never run the script by hand, see §2.2):
#   bazel run //tools/sync-env-secrets:apply   -- <github-environment>   # store -> GitHub env secrets
#   bazel run //tools/sync-env-secrets:bw-pull                            # Bitwarden -> store
#   bazel run //tools/sync-env-secrets:bw-push                            # store -> Bitwarden
#   bazel run //tools/sync-env-secrets:unlock                             # cache a bw session (run once)
#   bazel run //tools/sync-env-secrets:lock                               # clear the cached session + lock
#
# Env overrides: REPO (default VitruvianSoftware/vitruvian-core), BW_ITEM, BW_PASSWORD.
# Bitwarden unlock is folded in: `unlock` prompts once and caches the session
# (0600) so later bw-push/bw-pull/apply runs work headless (an agent or CI) until
# the vault relocks — no manual `export BW_SESSION` needed.
set -euo pipefail

REPO="${REPO:-VitruvianSoftware/vitruvian-core}"
# Under `bazel run`, operate on the real workspace tree — the gitignored secret
# store lives there, not in the read-only runfiles copy. Run directly, resolve
# next to this script so it still works outside bazel.
if [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
  BASE="$BUILD_WORKSPACE_DIRECTORY/tools/sync-env-secrets"
else
  BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
STORE="$BASE/secrets"
BW_ITEM="${BW_ITEM:-vitruvian-core/deploy-env-secrets}"
ARCHIVE_NAME="deploy-env-secrets.tar.gz"
# A one-time `:unlock` caches the unlocked session here (0600) so an agent/CI can
# drive bw-push/bw-pull/apply headless until the vault relocks; `:lock` clears it.
# A persistent vault session on disk is the deliberate tradeoff for unattended
# driving — lock it when you're done.
SESS_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/vitruvian-core/bw-session"

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

bw_state() { bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo unknown; }

# Resolve an unlocked BW_SESSION, in priority order: already-exported -> cached
# session file (lets an agent/CI drive headless) -> $BW_PASSWORD (non-interactive)
# -> interactive master-password prompt (a TTY, i.e. `bazel run` from a terminal).
ensure_bw_session() {
  command -v bw >/dev/null || die "bw (Bitwarden CLI) not installed: brew install bitwarden-cli"
  command -v jq >/dev/null || die "jq not installed"
  { [ -n "${BW_SESSION:-}" ] && [ "$(bw_state)" = unlocked ]; } && return 0
  if [ -z "${BW_SESSION:-}" ] && [ -r "$SESS_CACHE" ]; then
    BW_SESSION="$(cat "$SESS_CACHE")"
    export BW_SESSION
    [ "$(bw_state)" = unlocked ] && return 0
    unset BW_SESSION # cached session is stale (vault relocked)
  fi
  [ "$(bw_state)" != unauthenticated ] || die "not logged in to Bitwarden — run 'bw login' once, then retry"
  if [ -n "${BW_PASSWORD:-}" ]; then
    BW_SESSION="$(bw unlock --passwordenv BW_PASSWORD --raw)" || die "bw unlock failed (BW_PASSWORD)"
  elif [ -t 0 ]; then
    echo "Unlocking Bitwarden — enter your master password:" >&2
    BW_SESSION="$(bw unlock --raw)" || die "bw unlock failed"
  else
    die "Bitwarden locked and no usable cached session — run 'bazel run //tools/sync-env-secrets:unlock' once (it prompts), then retry headless"
  fi
  [ -n "${BW_SESSION:-}" ] || die "bw unlock returned an empty session"
  export BW_SESSION
}

# Persist the unlocked session (0600) so subsequent headless runs reuse it.
cache_session() {
  local old_umask
  old_umask="$(umask)"
  umask 077
  mkdir -p "$(dirname "$SESS_CACHE")"
  printf '%s' "${BW_SESSION:?no session to cache}" >"$SESS_CACHE"
  chmod 600 "$SESS_CACHE"
  umask "$old_umask"
}

# Guarded like sealed_secrets_keys.sh's item_id: a missing item or a transient bw
# error must not abort the caller under `set -o pipefail` before the not-found
# branch (create) can run.
bw_item_id() { bw list items --search "$BW_ITEM" 2>/dev/null | jq -r '.[0].id // empty' 2>/dev/null || true; }

cmd_bw_push() {
  ensure_bw_session
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
    # Remove EVERY prior copy of the attachment, and make a failed delete fatal:
    # a leftover duplicate would give bw-pull two same-named ids and break recovery.
    for att_old in $(bw get item "$id" | jq -r --arg n "$ARCHIVE_NAME" '.attachments[]? | select(.fileName==$n) | .id'); do
      bw delete attachment "$att_old" --itemid "$id" >/dev/null \
        || die "failed to remove a stale '$ARCHIVE_NAME' attachment — re-run, or delete it in the Bitwarden UI"
    done
  fi
  bw create attachment --itemid "$id" --file "$tar" >/dev/null
  echo "pushed $ARCHIVE_NAME to Bitwarden item '$BW_ITEM'"
}

cmd_bw_pull() {
  ensure_bw_session
  bw sync >/dev/null
  local id att tmpdir tar
  id="$(bw_item_id)"
  [ -n "$id" ] || die "no Bitwarden item '$BW_ITEM' — run 'bw-push' first"
  # first(...) so a stray duplicate attachment can't yield a malformed multi-id.
  att="$(bw get item "$id" | jq -r --arg n "$ARCHIVE_NAME" 'first(.attachments[]? | select(.fileName==$n) | .id) // empty')"
  [ -n "$att" ] || die "no '$ARCHIVE_NAME' attachment on item '$BW_ITEM'"
  tmpdir="$(mktemp -d)"
  _tmp_cleanup="$tmpdir"
  tar="$tmpdir/$ARCHIVE_NAME"
  bw get attachment "$att" --itemid "$id" --output "$tar" >/dev/null
  mkdir -p "$STORE"
  tar -xzf "$tar" -C "$STORE"
  echo "pulled store from Bitwarden item '$BW_ITEM' into $STORE"
}

cmd_unlock() {
  ensure_bw_session
  cache_session
  echo "✓ Bitwarden unlocked; session cached at $SESS_CACHE."
  echo "  apply / bw-push / bw-pull now run headless (agent or CI) until the vault relocks. Run 'lock' to clear."
}

cmd_lock() {
  rm -f "$SESS_CACHE"
  command -v bw >/dev/null && bw lock >/dev/null 2>&1 || true
  echo "✓ cleared the cached session and locked the vault."
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
  unlock)
    cmd_unlock
    ;;
  lock)
    cmd_lock
    ;;
  *)
    cat >&2 <<EOF
sync-env-secrets — manage non-GCP-SM deploy secrets as code (§2.2, §2.18)

Run via bazel (preferred):
  bazel run //tools/sync-env-secrets:apply   -- <github-environment>   # store -> GitHub env secrets
  bazel run //tools/sync-env-secrets:bw-pull                            # Bitwarden -> store
  bazel run //tools/sync-env-secrets:bw-push                            # store -> Bitwarden
  bazel run //tools/sync-env-secrets:unlock                             # cache a bw session (run once)
  bazel run //tools/sync-env-secrets:lock                               # clear the cached session + lock

store: $STORE/<github-environment>/<SECRET_NAME>   (gitignored; see secrets.example/)
EOF
    exit 2
    ;;
esac
