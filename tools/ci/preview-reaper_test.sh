#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Hermetic unit tests for preview-reaper.sh. Stubs gh, gcloud, kubectl, and curl
# to assert exact resource deletion, TTL handling, and safety exclusions.
set -uo pipefail

SCRIPT="${1:?usage: preview-reaper_test.sh <path to preview-reaper.sh>}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass_n=0
fail_n=0
pass() { echo "  ✓ $1"; pass_n=$((pass_n + 1)); }
fail() { echo "  ✗ $1" >&2; fail_n=$((fail_n + 1)); }

stubs="$work/stubs"
mkdir -p "$stubs"

# Log files for stub recording
export CR_DELETED="$work/cr_deleted"
export K8S_DELETED="$work/k8s_deleted"
export NEON_DELETED="$work/neon_deleted"

# 1. Stub gh
cat >"$stubs/gh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  num="${3:-}"
  for item in ${STUB_PRS//;/ }; do
    # format: num:state:age_hours
    IFS=: read -r p_num p_state p_age <<< "$item"
    if [ "$p_num" = "$num" ]; then
      # Calculate created ISO timestamp based on age in hours relative to NOW_EPOCH (1700000000)
      created_epoch=$(( 1700000000 - p_age * 3600 ))
      iso=$(python3 -c "import datetime, sys; print(datetime.datetime.fromtimestamp($created_epoch, tz=datetime.timezone.utc).isoformat())")
      printf '{"state":"%s","createdAt":"%s"}
' "$p_state" "$iso"
      exit 0
    fi
  done
  exit 1
fi
exit 0
EOF
chmod +x "$stubs/gh"

# 2. Stub gcloud
cat >"$stubs/gcloud" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "run" ] && [ "${2:-}" = "services" ] && [ "${3:-}" = "list" ]; then
  # Svc Name <TAB> Creation Timestamp
  printf 'tabula-api-pr-101	2023-11-14T10:00:00Z
'
  printf 'tabula-api-pr-102	2023-11-14T10:00:00Z
'
  printf 'tabula-api-pr-103	2023-11-14T20:00:00Z
'
  printf 'tabula-api-pr-104	2023-11-13T10:00:00Z
'
  printf 'tabula-api-pr-200	2023-11-14T20:00:00Z
'
  printf 'tabula-api-dev	2023-11-14T10:00:00Z
'
  printf 'tabula-api-prod	2023-11-14T10:00:00Z
'
  exit 0
fi
if [ "${1:-}" = "run" ] && [ "${2:-}" = "services" ] && [ "${3:-}" = "delete" ]; then
  echo "${4:-}" >> "$CR_DELETED"
  exit 0
fi
exit 0
EOF
chmod +x "$stubs/gcloud"

# 3. Stub kubectl
cat >"$stubs/kubectl" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "get" ] && [ "${2:-}" = "namespaces" ]; then
  printf 'pr-101	2023-11-14T10:00:00Z
'
  printf 'pr-102	2023-11-14T10:00:00Z
'
  printf 'pr-103	2023-11-14T20:00:00Z
'
  printf 'pr-104	2023-11-13T10:00:00Z
'
  printf 'pr-200	2023-11-14T20:00:00Z
'
  printf 'default	2023-11-14T10:00:00Z
'
  printf 'kube-system	2023-11-14T10:00:00Z
'
  printf 'argocd	2023-11-14T10:00:00Z
'
  exit 0
fi
if [ "${1:-}" = "delete" ] && [ "${2:-}" = "namespace" ]; then
  echo "${3:-}" >> "$K8S_DELETED"
  exit 0
fi
exit 0
EOF
chmod +x "$stubs/kubectl"

# 4. Stub curl for Neon
cat >"$stubs/curl" <<'EOF'
#!/usr/bin/env bash
# If GET branches
if [[ "$*" =~ "api/v2/projects/test-proj/branches" ]] && [[ ! "$*" =~ "-X DELETE" ]]; then
  cat <<'JSON'
{
  "branches": [
    {"id": "br-101", "name": "tabula-pr-101", "created_at": "2023-11-14T10:00:00Z", "primary": false},
    {"id": "br-102", "name": "tabula-pr-102", "created_at": "2023-11-14T10:00:00Z", "primary": false},
    {"id": "br-103", "name": "tabula-pr-103", "created_at": "2023-11-14T20:00:00Z", "primary": false},
    {"id": "br-104", "name": "tabula-pr-104", "created_at": "2023-11-13T10:00:00Z", "primary": false},
    {"id": "br-200", "name": "tabula-pr-200", "created_at": "2023-11-14T20:00:00Z", "primary": false},
    {"id": "br-main", "name": "main", "created_at": "2023-11-14T10:00:00Z", "primary": true}
  ]
}
JSON
  exit 0
fi
if [[ "$*" =~ "-X DELETE" ]]; then
  # Extract branch ID from URL
  echo "$*" | sed 's|.*/branches/||' | awk '{print $1}' >> "$NEON_DELETED"
  exit 0
fi
exit 0
EOF
chmod +x "$stubs/curl"

run() {
  local pr_arg="${1:-}"
  local dry_run="${2:-}"
  : > "$CR_DELETED"
  : > "$K8S_DELETED"
  : > "$NEON_DELETED"

  OUT="$(env PATH="$stubs:$PATH"       CR_DELETED="$CR_DELETED"       K8S_DELETED="$K8S_DELETED"       NEON_DELETED="$NEON_DELETED"       GCP_PROJECT="test-gcp"       NEON_API_KEY="test-key"       NEON_PROJECT_ID="test-proj"       PREVIEW_TTL_HOURS=24       NOW_EPOCH=1700000000       DRY_RUN="$dry_run"       STUB_PRS="101:MERGED:5;102:CLOSED:5;103:OPEN:2;104:OPEN:30;200:CLOSED:1"       bash "$SCRIPT" ${pr_arg:+"$pr_arg"} 2>"$work/err")"
}

echo "--- 1. Targeted PR mode ---"
run "200" ""
if [ "$(cat "$CR_DELETED")" = "tabula-api-pr-200" ] &&    [ "$(cat "$K8S_DELETED")" = "pr-200" ] &&    [ "$(cat "$NEON_DELETED")" = "br-200" ]; then
    pass "Targeted PR #200 deleted only PR 200 resources across Cloud Run, K8s, and Neon"
else
    fail "Targeted mode failed: CR=$(cat "$CR_DELETED"), K8S=$(cat "$K8S_DELETED"), NEON=$(cat "$NEON_DELETED")"
fi

echo "--- 2. Sweep mode (Closed, Merged, and TTL-expired) ---"
run "" ""
# Expected reaped: 101 (MERGED), 102 (CLOSED), 104 (OPEN but age 30h > 24h), 200 (CLOSED)
# Preserved: 103 (OPEN age 2h < 24h)
cr_sorted="$(sort "$CR_DELETED" | tr '
' ' ')"
if [ "$cr_sorted" = "tabula-api-pr-101 tabula-api-pr-102 tabula-api-pr-104 tabula-api-pr-200 " ]; then
    pass "Cloud Run reaped merged, closed, and expired PRs; preserved active PR 103"
else
    fail "Cloud Run sweep mismatch: got '$cr_sorted'"
fi

k8s_sorted="$(sort "$K8S_DELETED" | tr '
' ' ')"
if [ "$k8s_sorted" = "pr-101 pr-102 pr-104 pr-200 " ]; then
    pass "Kubernetes reaped merged, closed, and expired namespaces"
else
    fail "Kubernetes sweep mismatch: got '$k8s_sorted'"
fi

neon_sorted="$(sort "$NEON_DELETED" | tr '
' ' ')"
if [ "$neon_sorted" = "br-101 br-102 br-104 br-200 " ]; then
    pass "Neon branches reaped merged, closed, and expired branches"
else
    fail "Neon sweep mismatch: got '$neon_sorted'"
fi

echo "--- 3. Negative safety tests (Protected environments) ---"
if grep -qE "tabula-api-dev|tabula-api-prod" "$CR_DELETED"; then
    fail "CRITICAL: Deleted protected Cloud Run services!"
else
    pass "Protected Cloud Run services (dev/prod) were never targeted"
fi

if grep -qE "default|kube-system|argocd" "$K8S_DELETED"; then
    fail "CRITICAL: Deleted protected Kubernetes namespaces!"
else
    pass "Protected Kubernetes namespaces were never targeted"
fi

if grep -qE "br-main|main" "$NEON_DELETED"; then
    fail "CRITICAL: Deleted protected Neon primary branch!"
else
    pass "Protected Neon primary branch was never targeted"
fi

echo "--- 4. DRY_RUN mode ---"
run "" "1"
if [ -s "$CR_DELETED" ] || [ -s "$K8S_DELETED" ] || [ -s "$NEON_DELETED" ]; then
    fail "DRY_RUN mode executed real deletion calls!"
else
    pass "DRY_RUN mode made 0 delete calls while computing accurate summary metrics"
fi

echo "--- 5. Output format verification ---"
run "" ""
lines_count="$(echo "$OUT" | grep -cE '^(reaped_cloudrun|reaped_k8s|reaped_neon|total_reaped)=[0-9]+$')"
if [ "$lines_count" -eq 4 ]; then
    pass "Output matches exact 4-line GITHUB_OUTPUT format"
else
    fail "Output did not match GITHUB_OUTPUT format: '$OUT'"
fi

echo
if [ "$fail_n" -gt 0 ]; then
    echo "FAILED: $fail_n test(s)"
    exit 1
fi
echo "ALL PASS ($pass_n)"
