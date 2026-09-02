#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# pr-comment.sh — Idempotent GitHub PR Sticky Comment Bot for Ephemeral Previews.
set -euo pipefail

PR_NUMBER=""
APP=""
STATUS="ready"
PREVIEW_URL=""
SERVICE_NAME=""
DB_BRANCH=""
REPO="${GITHUB_REPOSITORY:-VitruvianSoftware/vitruvian-core}"
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $(basename "$0") --pr <number> --app <name> --status <status> [options]

Required:
  --pr <number>              Pull Request number
  --app <name>               Application name (e.g. tabula)
  --status <status>          Status: provisioning | ready | failed | teardown

Options:
  --preview-url <url>        Live preview environment URL
  --service-name <name>      Cloud Run service name or K8s namespace
  --db-branch <name>         Neon database branch name
  --repo <owner/repo>        GitHub repository (default: VitruvianSoftware/vitruvian-core)
  --dry-run                  Simulate comment rendering and API calls
  -h, --help                 Show this help message
EOF
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --pr) PR_NUMBER="$2"; shift 2 ;;
    --app) APP="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --preview-url) PREVIEW_URL="$2"; shift 2 ;;
    --service-name) SERVICE_NAME="$2"; shift 2 ;;
    --db-branch) DB_BRANCH="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage 1 ;;
  esac
done

if [ -z "$PR_NUMBER" ] || [ -z "$APP" ]; then
  echo "ERROR: --pr and --app are required" >&2
  usage 1
fi

MARKER="<!-- vitruvian-preview-bot: ${APP} -->"

render_comment_body() {
  local timestamp
  timestamp="$(date -u +"%Y-%m-%d %H:%M:%S UTC")"

  case "$STATUS" in
    provisioning)
      cat <<EOF
### ⏳ Ephemeral Preview Environment Provisioning
The preview environment for **${APP}** is currently being built and deployed.

- **PR:** #${PR_NUMBER}
- **Timestamp:** ${timestamp}
- **Status:** Provisioning in progress...

${MARKER}
EOF
      ;;
    ready)
      cat <<EOF
### 🚀 Ephemeral Preview Environment Ready

| Resource | Details |
|---|---|
| **Application** | \`${APP}\` |
| **Preview URL** | [${PREVIEW_URL}](${PREVIEW_URL}) |
| **Compute Service** | \`${SERVICE_NAME}\` |
| **Database Branch** | \`${DB_BRANCH}\` (Neon copy-on-write) |
| **Access Gating** | 🔒 Zero-Trust SSO (\`@vitruviansoftware.dev\`) |
| **Status** | ✅ Healthy (HTTP 200) |
| **TTL** | ⏱️ 24 hours (Auto-teardown on PR close or reaper) |

*Last updated: ${timestamp}*

${MARKER}
EOF
      ;;
    failed)
      cat <<EOF
### ❌ Ephemeral Preview Provisioning Failed
Provisioning for **${APP}** failed during rollout. Please inspect the CI workflow logs.

- **PR:** #${PR_NUMBER}
- **Timestamp:** ${timestamp}

${MARKER}
EOF
      ;;
    teardown)
      cat <<EOF
### 🧹 Ephemeral Preview Environment Destroyed
The ephemeral preview environment for **${APP}** has been torn down.

- **PR:** #${PR_NUMBER}
- **Cloud Run Service:** Deleted
- **Neon DB Branch:** Deleted
- **Timestamp:** ${timestamp}

${MARKER}
EOF
      ;;
    *)
      echo "ERROR: Unknown status '$STATUS'" >&2
      exit 1
      ;;
  esac
}

BODY="$(render_comment_body)"

if [ "$DRY_RUN" = true ]; then
  echo "=== DRY RUN: PR Sticky Comment Body ==="
  echo "$BODY"
  echo "========================================"
  exit 0
fi

# Find existing comment with marker
EXISTING_ID="$(gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" --jq ".[] | select(.body | contains(\"${MARKER}\")) | .id" | head -n 1)"

if [ -n "$EXISTING_ID" ]; then
  echo "Updating existing PR comment (ID: ${EXISTING_ID})..."
  gh api -X PATCH "repos/${REPO}/issues/comments/${EXISTING_ID}" -f body="$BODY" >/dev/null
  echo "✓ PR comment updated."
else
  echo "Creating new PR comment on #${PR_NUMBER}..."
  gh api -X POST "repos/${REPO}/issues/${PR_NUMBER}/comments" -f body="$BODY" >/dev/null
  echo "✓ PR comment created."
fi
