#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# neon-branch.sh — Provision and manage copy-on-write Neon Postgres database branches
# for PR ephemeral preview environments.
set -euo pipefail

API_URL="${NEON_API_URL:-https://console.neon.tech/api/v2}"
PROJECT_ID="${NEON_PROJECT_ID:-}"
API_KEY="${NEON_API_KEY:-}"
BRANCH_NAME="${NEON_BRANCH_NAME:-}"
PARENT_ID="${NEON_PARENT_ID:-main}"
FORMAT="json"
DRY_RUN=false
ACTION=""

usage() {
  cat <<EOF
Usage: $(basename "$0") <create|delete|get> [options]

Actions:
  create    Create a new branch and compute endpoint; print connection info
  delete    Delete an existing branch (idempotent)
  get       Fetch connection info for an existing branch

Options:
  --project-id <id>     Neon Project ID [REQUIRED]
  --api-key <key>       Neon API Key [REQUIRED]
  --branch-name <name>  Branch name [REQUIRED]
  --parent-id <id>      Parent branch name or ID (default: main)
  --api-url <url>       Neon API base URL (default: https://console.neon.tech/api/v2)
  --format <json|url>   Output format (default: json)
  --dry-run             Show planned actions without calling the API
  -h, --help            Show this help message
EOF
  exit "${1:-0}"
}

# Parse positional action
if [ $# -ge 1 ] && [[ "$1" =~ ^(create|delete|get)$ ]]; then
  ACTION="$1"
  shift
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --project-id) PROJECT_ID="$2"; shift 2 ;;
    --api-key) API_KEY="$2"; shift 2 ;;
    --branch-name) BRANCH_NAME="$2"; shift 2 ;;
    --parent-id) PARENT_ID="$2"; shift 2 ;;
    --api-url) API_URL="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage 1 ;;
  esac
done

if [ -z "$ACTION" ]; then
  echo "ERROR: Missing action (create, delete, get)" >&2
  usage 1
fi

if [ "$DRY_RUN" = false ]; then
  if [ -z "$PROJECT_ID" ]; then
    echo "ERROR: --project-id or NEON_PROJECT_ID is required" >&2
    exit 1
  fi
  if [ -z "$API_KEY" ]; then
    echo "ERROR: --api-key or NEON_API_KEY is required" >&2
    exit 1
  fi
  if [ -z "$BRANCH_NAME" ]; then
    echo "ERROR: --branch-name or NEON_BRANCH_NAME is required" >&2
    exit 1
  fi
fi

# Helper: make authenticated Neon API request
api_request() {
  local method="$1"
  local path="$2"
  local data="${3:-}"

  local url="${API_URL%/}/${path#/}"
  local auth_header="Authorization: Bearer ${API_KEY}"
  local content_header="Content-Type: application/json"

  if [ -n "$data" ]; then
    curl -sS -f -X "$method" -H "$auth_header" -H "$content_header" -d "$data" "$url"
  else
    curl -sS -f -X "$method" -H "$auth_header" -H "$content_header" "$url"
  fi
}

# Resolve parent branch ID
resolve_parent_branch_id() {
  local branches_json
  branches_json="$(api_request GET "projects/${PROJECT_ID}/branches")"
  
  # Search by ID or Name
  local id
  id="$(echo "$branches_json" | jq -r --arg p "$PARENT_ID" '.branches[] | select(.id == $p or .name == $p) | .id' | head -n 1)"
  if [ -z "$id" ] || [ "$id" = "null" ]; then
    echo "ERROR: Parent branch '$PARENT_ID' not found in project '$PROJECT_ID'" >&2
    exit 1
  fi
  echo "$id"
}

# Find branch by name
find_branch_by_name() {
  local name="$1"
  local branches_json
  branches_json="$(api_request GET "projects/${PROJECT_ID}/branches")"
  echo "$branches_json" | jq -r --arg n "$name" '.branches[] | select(.name == $n)'
}

# Get endpoint host for branch
get_branch_endpoint() {
  local branch_id="$1"
  local endpoints_json
  endpoints_json="$(api_request GET "projects/${PROJECT_ID}/endpoints")"
  echo "$endpoints_json" | jq -r --arg b "$branch_id" '.endpoints[] | select(.branch_id == $b) | .host' | head -n 1
}

# Action: create
do_create() {
  if [ "$DRY_RUN" = true ]; then
    cat <<EOF
{
  "dry_run": true,
  "action": "create",
  "project_id": "${PROJECT_ID:-dry-run-project}",
  "branch_name": "${BRANCH_NAME:-dry-run-branch}",
  "parent_id": "${PARENT_ID}",
  "database_url": "postgresql://neondb_owner:mock_password@ep-dry-run-123456.us-central-1.aws.neon.tech/neondb?sslmode=require"
}
EOF
    return 0
  fi

  local existing_branch
  existing_branch="$(find_branch_by_name "$BRANCH_NAME")"

  local branch_id=""
  local host=""

  if [ -n "$existing_branch" ] && [ "$existing_branch" != "null" ]; then
    branch_id="$(echo "$existing_branch" | jq -r '.id')"
  else
    local parent_branch_id
    parent_branch_id="$(resolve_parent_branch_id)"
    
    local payload
    payload="$(jq -n --arg name "$BRANCH_NAME" --arg parent "$parent_branch_id"       '{branch: {name: $name, parent_id: $parent}, endpoints: [{type: "read_write"}]}')"
    
    local create_resp
    create_resp="$(api_request POST "projects/${PROJECT_ID}/branches" "$payload")"
    branch_id="$(echo "$create_resp" | jq -r '.branch.id')"
  fi

  # Resolve compute endpoint host
  host="$(get_branch_endpoint "$branch_id")"
  
  # Fetch connection URI
  local uri_resp
  uri_resp="$(api_request GET "projects/${PROJECT_ID}/connection_uri?branch_id=${branch_id}&database_name=neondb&role_name=neondb_owner")"
  local db_url
  db_url="$(echo "$uri_resp" | jq -r '.uri // empty')"
  if [ -z "$db_url" ]; then
    db_url="postgresql://neondb_owner@${host}/neondb?sslmode=require"
  fi

  if [ "$FORMAT" = "url" ]; then
    echo "$db_url"
  else
    jq -n       --arg project_id "$PROJECT_ID"       --arg branch_id "$branch_id"       --arg branch_name "$BRANCH_NAME"       --arg host "$host"       --arg db_url "$db_url"       '{
        project_id: $project_id,
        branch_id: $branch_id,
        branch_name: $branch_name,
        host: $host,
        database_url: $db_url,
        status: "ready"
      }'
  fi
}

# Action: delete
do_delete() {
  if [ "$DRY_RUN" = true ]; then
    echo "{\"dry_run\": true, \"action\": \"delete\", \"branch_name\": \"${BRANCH_NAME:-dry-run-branch}\"}"
    return 0
  fi

  local existing_branch
  existing_branch="$(find_branch_by_name "$BRANCH_NAME")"
  if [ -z "$existing_branch" ] || [ "$existing_branch" = "null" ]; then
    echo "{\"status\": \"not_found\", \"branch_name\": \"$BRANCH_NAME\", \"message\": \"Branch does not exist, nothing to delete\"}"
    return 0
  fi

  local branch_id
  branch_id="$(echo "$existing_branch" | jq -r '.id')"
  api_request DELETE "projects/${PROJECT_ID}/branches/${branch_id}" >/dev/null

  echo "{\"status\": \"deleted\", \"branch_id\": \"$branch_id\", \"branch_name\": \"$BRANCH_NAME\"}"
}

# Action: get
do_get() {
  if [ "$DRY_RUN" = true ]; then
    echo "{\"dry_run\": true, \"action\": \"get\", \"branch_name\": \"${BRANCH_NAME:-dry-run-branch}\"}"
    return 0
  fi

  local existing_branch
  existing_branch="$(find_branch_by_name "$BRANCH_NAME")"
  if [ -z "$existing_branch" ] || [ "$existing_branch" = "null" ]; then
    echo "ERROR: Branch '$BRANCH_NAME' not found" >&2
    exit 1
  fi

  local branch_id
  branch_id="$(echo "$existing_branch" | jq -r '.id')"
  local host
  host="$(get_branch_endpoint "$branch_id")"
  
  local uri_resp
  uri_resp="$(api_request GET "projects/${PROJECT_ID}/connection_uri?branch_id=${branch_id}&database_name=neondb&role_name=neondb_owner")"
  local db_url
  db_url="$(echo "$uri_resp" | jq -r '.uri // empty')"

  if [ "$FORMAT" = "url" ]; then
    echo "$db_url"
  else
    jq -n       --arg project_id "$PROJECT_ID"       --arg branch_id "$branch_id"       --arg branch_name "$BRANCH_NAME"       --arg host "$host"       --arg db_url "$db_url"       '{
        project_id: $project_id,
        branch_id: $branch_id,
        branch_name: $branch_name,
        host: $host,
        database_url: $db_url
      }'
  fi
}

case "$ACTION" in
  create) do_create ;;
  delete) do_delete ;;
  get) do_get ;;
esac
