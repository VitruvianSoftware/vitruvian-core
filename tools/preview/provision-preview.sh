#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# provision-preview.sh — Ephemeral Preview Environment Provisioning Engine.
# Deploys isolated Cloud Run services or K8s namespaces with Neon database branches.
set -euo pipefail

APP=""
PR_NUMBER=""
IMAGE_DIGEST=""
MODE="cloud-run"
GCP_PROJECT="${GCP_PROJECT_ID:-}"
REGION="${GCP_REGION:-us-central1}"
NEON_PROJECT_ID="${NEON_PROJECT_ID:-}"
SMOKE_PATH="/health"
DOMAIN_BASE="preview.vitruviansoftware.dev"
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $(basename "$0") --app <name> --pr <number> [options]

Required:
  --app <name>               Application name (e.g. tabula-api, oauth-user-inspector)
  --pr <number>              Pull Request number (e.g. 142)

Options:
  --image-digest <ref>       Container image digest (sha256:...)
  --mode <cloud-run|k8s>     Compute mode (default: cloud-run)
  --project <id>             GCP Project ID (env: GCP_PROJECT_ID)
  --region <region>          GCP Region (default: us-central1)
  --neon-project-id <id>     Neon Project ID for Postgres branching
  --smoke-path <path>        Path for candidate health check (default: /health)
  --domain-base <domain>     Base preview domain (default: preview.vitruviansoftware.dev)
  --dry-run                  Simulate provisioning without making changes
  -h, --help                 Show this help message
EOF
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --pr) PR_NUMBER="$2"; shift 2 ;;
    --image-digest) IMAGE_DIGEST="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --project) GCP_PROJECT="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --neon-project-id) NEON_PROJECT_ID="$2"; shift 2 ;;
    --smoke-path) SMOKE_PATH="$2"; shift 2 ;;
    --domain-base) DOMAIN_BASE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage 1 ;;
  esac
done

if [ -z "$APP" ] || [ -z "$PR_NUMBER" ]; then
  echo "ERROR: --app and --pr are required" >&2
  usage 1
fi

if [ "$DRY_RUN" = false ] && [ "$MODE" = "cloud-run" ]; then
  if [ -z "$IMAGE_DIGEST" ]; then
    echo "ERROR: --image-digest is required in cloud-run mode" >&2
    exit 1
  fi
  if [ -z "$GCP_PROJECT" ]; then
    echo "ERROR: --project or GCP_PROJECT_ID is required" >&2
    exit 1
  fi
fi

SERVICE_NAME="${APP}-pr-${PR_NUMBER}"
BRANCH_NAME="${APP}-pr-${PR_NUMBER}"
PREVIEW_HOSTNAME="pr-${PR_NUMBER}.${APP}.${DOMAIN_BASE}"
PREVIEW_URL="https://${PREVIEW_HOSTNAME}"

log() { echo "$*" >&2; }

log "============================================================"
log "🚀 Ephemeral Preview Provisioning Engine"
log "  Application:   ${APP}"
log "  PR Number:     #${PR_NUMBER}"
log "  Mode:          ${MODE}"
log "  Service Name:  ${SERVICE_NAME}"
log "  Preview Host:  ${PREVIEW_HOSTNAME}"
log "============================================================"

# Step 1: Stateful Tier Provisioning (Neon Branch)
DATABASE_URL=""
if [ -n "$NEON_PROJECT_ID" ]; then
  log "📦 Step 1: Provisioning Neon Postgres Branch '${BRANCH_NAME}'..."
  if [ "$DRY_RUN" = true ]; then
    DATABASE_URL="postgresql://neondb_owner:mock@ep-mock.neon.tech/neondb?sslmode=require"
    log "   [DRY-RUN] Neon Branch simulated: ${DATABASE_URL}"
  else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    NEON_OUT="$("${SCRIPT_DIR}/neon-branch.sh" create       --project-id "$NEON_PROJECT_ID"       --branch-name "$BRANCH_NAME"       --format json)"
    DATABASE_URL="$(echo "$NEON_OUT" | jq -r '.database_url')"
    log "   ✓ Neon Branch ready: $(echo "$NEON_OUT" | jq -r '.host')"
  fi
else
  log "⏩ Step 1: No Neon Project ID specified; skipping database branching."
fi

# Step 2: Compute Provisioning
SERVICE_URI=""
if [ "$MODE" = "cloud-run" ]; then
  log "☁️ Step 2: Deploying Cloud Run v2 service '${SERVICE_NAME}' in '${REGION}'..."
  if [ "$DRY_RUN" = true ]; then
    SERVICE_URI="https://${SERVICE_NAME}-preview-uc.a.run.app"
    log "   [DRY-RUN] Cloud Run Service simulated at ${SERVICE_URI}"
  else
    # Build env vars list
    ENV_VARS="NODE_ENV=preview,PREVIEW_PR_NUMBER=${PR_NUMBER},API_URL=${PREVIEW_URL}"
    if [ -n "$DATABASE_URL" ]; then
      ENV_VARS="${ENV_VARS},DATABASE_URL=${DATABASE_URL}"
    fi

    # Deploy Cloud Run service
    gcloud run deploy "$SERVICE_NAME"       --project "$GCP_PROJECT"       --region "$REGION"       --image "$IMAGE_DIGEST"       --set-env-vars "$ENV_VARS"       --allow-unauthenticated       --port 8080       --quiet

    SERVICE_URI="$(gcloud run services describe "$SERVICE_NAME"       --project "$GCP_PROJECT"       --region "$REGION"       --format 'value(status.url)')"
    log "   ✓ Cloud Run Service deployed at ${SERVICE_URI}"
  fi
elif [ "$MODE" = "k8s" ]; then
  log "☸️ Step 2: Provisioning Kubernetes namespace 'pr-${PR_NUMBER}'..."
  if [ "$DRY_RUN" = true ]; then
    SERVICE_URI="https://pr-${PR_NUMBER}.${APP}.lab.ipv1337.dev"
    log "   [DRY-RUN] Kubernetes Deployment simulated at ${SERVICE_URI}"
  else
    kubectl create namespace "pr-${PR_NUMBER}" --dry-run=client -o yaml | kubectl apply -f -
    if [ -n "$DATABASE_URL" ]; then
      kubectl create secret generic app-db-secrets         --namespace "pr-${PR_NUMBER}"         --from-literal="DATABASE_URL=${DATABASE_URL}"         --dry-run=client -o yaml | kubectl apply -f -
    fi
    SERVICE_URI="https://pr-${PR_NUMBER}.${APP}.lab.ipv1337.dev"
  fi
fi

# Step 3: Candidate Smoke Check
log "🔍 Step 3: Running Candidate Health Smoke Check..."
if [ "$DRY_RUN" = true ]; then
  log "   [DRY-RUN] Smoke check HTTP GET ${SERVICE_URI}${SMOKE_PATH} -> 200 OK"
else
  SMOKE_TARGET="${SERVICE_URI%/}${SMOKE_PATH}"
  log "   Pinging ${SMOKE_TARGET}..."
  status_code="$(curl -s -o /dev/null -w "%{http_code}" "$SMOKE_TARGET" || echo "000")"
  if [ "$status_code" != "200" ] && [ "$status_code" != "301" ] && [ "$status_code" != "302" ]; then
    log "   ⚠️ Warning: Candidate smoke returned HTTP ${status_code}; check service logs"
  else
    log "   ✓ Candidate smoke passed (HTTP ${status_code})"
  fi
fi

# Step 4: Emit Structured Output
log "✅ Step 4: Preview Environment Ready!"
jq -n   --arg app "$APP"   --arg pr "$PR_NUMBER"   --arg service_name "$SERVICE_NAME"   --arg service_url "$SERVICE_URI"   --arg preview_url "$PREVIEW_URL"   --arg db_branch "$BRANCH_NAME"   --arg db_url "$DATABASE_URL"   --arg status "ready"   '{
    app: $app,
    pr_number: $pr,
    service_name: $service_name,
    service_url: $service_url,
    preview_url: $preview_url,
    database_branch: (if $db_url != "" then $db_branch else null end),
    database_url: (if $db_url != "" then $db_url else null end),
    status: $status
  }'
