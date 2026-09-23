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
#
# Pin the dev-local Argo CD `admin` password to a value held in Bitwarden.
#
# Why: without a pinned password, Argo CD generates a random one on install
# (argocd-initial-admin-secret). After the 2026-09-23 incident a reinstall
# silently changed the login. This makes Bitwarden the source of truth:
#
#   Bitwarden item "argocd admin (dev-local)"  (plaintext, username admin)
#     -> bcrypt hash + fixed mtime in the dev-local Pulumi stack config
#        (argocd_admin_password_bcrypt [secret], argocd_admin_password_mtime)
#     -> Helm configs.secret.argocdServerAdminPassword on the next `pulumi up`.
#
# Idempotent: when the stored hash already matches the Bitwarden password it
# changes nothing, so the mtime stays put and nobody is logged out.
#
# First run with no Bitwarden item: it seeds the item from the CURRENT live
# password (argocd-initial-admin-secret) so the login in use keeps working,
# falling back to a random 32-char password if that secret is gone.
#
# Must run from the checkout that holds the gitignored Pulumi.local.yaml (the
# main checkout, not a worktree) -- see infrastructure/pulumi/platform/dev-local/stackguard.go.
#
#   bazel run //tools/sync-env-secrets:unlock        # once, if the vault is locked
#   bazel run //tools/argocd-admin-password:sync
#   bazel run //infrastructure/pulumi/platform/dev-local:preview   # then :up

set -euo pipefail

ITEM="argocd admin (dev-local)"
URL="https://argocd.lab.ipv1337.dev"
PROJECT_DIR="infrastructure/pulumi/platform/dev-local"
SESS_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/vitruvian-core/bw-session"

die() { echo "argocd-admin-password: $*" >&2; exit 1; }

cd "${BUILD_WORKSPACE_DIRECTORY:?run via 'bazel run //tools/argocd-admin-password:sync'}/$PROJECT_DIR"
grep -q 'argocd_enabled' Pulumi.local.yaml 2>/dev/null ||
  die "no Pulumi.local.yaml with argocd_enabled in $PWD (worktree?). Run this from the main checkout."

export PULUMI_BACKEND_URL="${PULUMI_BACKEND_URL:-https://api.pulumi.com}"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/cluster.yaml}"
export GOWORK=off
STACK=(--stack local)

if [ -z "${BW_SESSION:-}" ] && [ -r "$SESS_CACHE" ]; then BW_SESSION="$(cat "$SESS_CACHE")"; export BW_SESSION; fi
[ "$(bw status 2>/dev/null | jq -r .status)" = unlocked ] ||
  die "Bitwarden is locked. Run: bazel run //tools/sync-env-secrets:unlock"
bw sync >/dev/null 2>&1 || true

item_json() { bw list items --search "$ITEM" 2>/dev/null | jq -c --arg n "$ITEM" '[.[] | select(.name==$n)][0] // empty'; }

item="$(item_json)"
if [ -z "$item" ]; then
  seed="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"
  if [ -n "$seed" ]; then src="the current live password (argocd-initial-admin-secret)"; else
    seed="$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 32)"; src="a new random password"; fi
  jq -nc --arg n "$ITEM" --arg p "$seed" --arg u "$URL" \
    '{type:1, name:$n, notes:"Managed by //tools/argocd-admin-password. Change the password here, then re-run :sync and pulumi up.",
      login:{username:"admin", password:$p, uris:[{uri:$u}]}}' | bw encode | bw create item >/dev/null
  echo "Created Bitwarden item \"$ITEM\" from $src."
  unset seed
  item="$(item_json)"
  [ -n "$item" ] || die "created the Bitwarden item but cannot read it back"
fi
password="$(jq -r '.login.password // empty' <<<"$item")"
[ -n "$password" ] || die "Bitwarden item \"$ITEM\" has no password"

current_hash="$(pulumi config get argocd_admin_password_bcrypt "${STACK[@]}" 2>/dev/null || true)"
current_mtime="$(pulumi config get argocd_admin_password_mtime "${STACK[@]}" 2>/dev/null || true)"
if [ -n "$current_hash" ] && [ -n "$current_mtime" ]; then
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
  printf 'admin:%s\n' "$current_hash" >"$tmp"
  if printf '%s' "$password" | htpasswd -vi "$tmp" admin >/dev/null 2>&1; then
    echo "Already in sync: the stack config hash matches Bitwarden (mtime $current_mtime). Nothing to do."
    exit 0
  fi
fi

# Argo CD wants the \$2a bcrypt prefix; the \$ in the sed pattern is literal.
# shellcheck disable=SC2016
hash="$(printf '%s' "$password" | htpasswd -niBC 10 "" | tr -d ':\n' | sed 's/^\$2y/$2a/')"
unset password
case "$hash" in \$2a\$10\$*) ;; *) die "unexpected bcrypt output" ;; esac
mtime="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
pulumi config set --secret argocd_admin_password_bcrypt "${STACK[@]}" -- "$hash" >/dev/null
pulumi config set --plaintext argocd_admin_password_mtime "${STACK[@]}" -- "$mtime" >/dev/null
echo "Stack config updated (mtime $mtime). Apply with:"
echo "  bazel run //$PROJECT_DIR:preview   then   bazel run //$PROJECT_DIR:up"
