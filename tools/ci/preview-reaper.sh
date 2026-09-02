#!/usr/bin/env bash
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

# preview-reaper.sh — Purge closed, merged, and TTL-expired ephemeral preview
# environments across Cloud Run, Kubernetes, and Neon Postgres branches.
#
# Usage:
#   preview-reaper.sh            # Sweep all preview resources (cron / reaper)
#   preview-reaper.sh <pr_num>   # Target a single closed PR (event-driven hook)
#   DRY_RUN=1 preview-reaper.sh  # Report candidates without deleting
#
# Environment variables:
#   REPO: Owner/repo (default: VitruvianSoftware/vitruvian-core)
#   GH: Path to gh binary (default: gh)
#   GCLOUD: Path to gcloud binary (default: gcloud)
#   KUBECTL: Path to kubectl binary (default: kubectl)
#   CURL: Path to curl binary (default: curl)
#   GCP_PROJECT: GCP Project ID for Cloud Run
#   GCP_REGION: GCP Region for Cloud Run (default: us-central1)
#   NEON_API_KEY: Neon API Token
#   NEON_PROJECT_ID: Neon Project ID
#   PREVIEW_TTL_HOURS: Hours before an open PR preview expires (default: 24)
#   DRY_RUN: Set to 1 to simulate deletions
#   NOW_EPOCH: Timestamp override for hermetic testing

set -euo pipefail

REPO="${REPO:-VitruvianSoftware/vitruvian-core}"
GH="${GH:-gh}"
GCLOUD="${GCLOUD:-gcloud}"
KUBECTL="${KUBECTL:-kubectl}"
CURL="${CURL:-curl}"
GCP_PROJECT="${GCP_PROJECT:-}"
GCP_REGION="${GCP_REGION:-us-central1}"
NEON_API_KEY="${NEON_API_KEY:-}"
NEON_PROJECT_ID="${NEON_PROJECT_ID:-}"
PREVIEW_TTL_HOURS="${PREVIEW_TTL_HOURS:-24}"
DRY_RUN="${DRY_RUN:-}"
NOW_EPOCH="${NOW_EPOCH:-$(date +%s)}"
ONLY_PR="${1:-}"

log() { echo "preview-reaper: $*" >&2; }

# Validate input PR if supplied
if [ -n "$ONLY_PR" ]; then
    if ! [[ "$ONLY_PR" =~ ^[0-9]+$ ]]; then
        log "ERROR: PR number must be positive integer, got '$ONLY_PR'"
        exit 2
    fi
fi

# Protected resource name regex: NEVER delete production or permanent environments
is_protected() {
    local name="$1"
    case "$name" in
        main|master|production|prod|nonproduction|nonprod|staging|development|dev|default|kube-system|kube-public|kube-node-lease|argocd|ingress-nginx)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Portable ISO8601 to Unix epoch converter
iso_to_epoch() {
    local iso="$1"
    python3 -c '
import sys, datetime
s = sys.argv[1].strip()
if not s:
    print(0)
    sys.exit(0)
try:
    s = s.replace("Z", "+00:00")
    dt = datetime.datetime.fromisoformat(s)
    print(int(dt.timestamp()))
except Exception:
    print(0)
' "$iso" 2>/dev/null || echo 0
}

# Cache PR status lookups to prevent duplicate GitHub API calls
TMP_DIR="${TMPDIR:-/tmp}/preview-reaper.$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

state_of_pr() {
    local num="$1"
    local cache_file="$TMP_DIR/pr-$num.json"
    if [ ! -f "$cache_file" ]; then
        if command -v "$GH" >/dev/null 2>&1; then
            "$GH" pr view "$num" --repo "$REPO" --json state,createdAt,updatedAt > "$cache_file" 2>/dev/null || echo '{"state":"UNKNOWN","createdAt":""}' > "$cache_file"
        else
            echo '{"state":"UNKNOWN","createdAt":""}' > "$cache_file"
        fi
    fi
    cat "$cache_file"
}

should_reap_pr() {
    local num="$1"
    local resource_created_epoch="${2:-0}"

    # In targeted mode, delete unconditionally
    if [ -n "$ONLY_PR" ] && [ "$num" = "$ONLY_PR" ]; then
        return 0
    fi

    local pr_json
    pr_json="$(state_of_pr "$num")"
    local state
    state="$(python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get("state", "UNKNOWN"))' <<< "$pr_json" 2>/dev/null || echo "UNKNOWN")"
    local created_at
    created_at="$(python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get("createdAt", ""))' <<< "$pr_json" 2>/dev/null || echo "")"

    case "$state" in
        MERGED|CLOSED)
            log "PR #$num is $state — marked for reap"
            return 0
            ;;
        OPEN)
            local pr_created_epoch
            pr_created_epoch="$(iso_to_epoch "$created_at")"
            local ref_epoch="$pr_created_epoch"
            if [ "$resource_created_epoch" -gt 0 ]; then
                ref_epoch="$resource_created_epoch"
            fi

            if [ "$ref_epoch" -gt 0 ]; then
                local age_seconds=$((NOW_EPOCH - ref_epoch))
                local ttl_seconds=$((PREVIEW_TTL_HOURS * 3600))
                if [ "$age_seconds" -gt "$ttl_seconds" ]; then
                    log "PR #$num is OPEN but age ($((age_seconds / 3600))h) exceeds TTL (${PREVIEW_TTL_HOURS}h) — marked for reap"
                    return 0
                else
                    log "PR #$num is OPEN and active ($((age_seconds / 3600))h / ${PREVIEW_TTL_HOURS}h) — preserving"
                    return 1
                fi
            else
                log "PR #$num is OPEN (unknown age) — preserving"
                return 1
            fi
            ;;
        *)
            log "PR #$num state is $state (unverifiable) — preserving as fail-safe"
            return 1
            ;;
    esac
}

reaped_cloudrun=0
reaped_k8s=0
reaped_neon=0

# ---------------------------------------------------------------------------
# 1. Cloud Run Preview Reclamation
# ---------------------------------------------------------------------------
reap_cloudrun() {
    if ! command -v "$GCLOUD" >/dev/null 2>&1 || [ -z "$GCP_PROJECT" ]; then
        log "gcloud not found or GCP_PROJECT unset — skipping Cloud Run reap"
        return 0
    fi

    log "Scanning Cloud Run preview services in project $GCP_PROJECT..."
    local services
    services="$("$GCLOUD" run services list --project="$GCP_PROJECT" --format="value(metadata.name,metadata.creationTimestamp)" 2>/dev/null || true)"

    while IFS=$'\t' read -r svc_name creation_ts; do
        [ -n "${svc_name:-}" ] || continue
        if is_protected "$svc_name"; then
            continue
        fi

        # Match preview service pattern: *-pr-<number>
        if [[ "$svc_name" =~ -pr-([0-9]+)$ ]]; then
            local pr_num="${BASH_REMATCH[1]}"
            if [ -n "$ONLY_PR" ] && [ "$pr_num" != "$ONLY_PR" ]; then
                continue
            fi

            local svc_epoch=0
            if [ -n "${creation_ts:-}" ]; then
                svc_epoch="$(iso_to_epoch "$creation_ts")"
            fi

            if should_reap_pr "$pr_num" "$svc_epoch"; then
                if [ -n "$DRY_RUN" ]; then
                    log "[DRY_RUN] Would delete Cloud Run service '$svc_name' (PR #$pr_num)"
                    reaped_cloudrun=$((reaped_cloudrun + 1))
                else
                    log "Deleting Cloud Run service '$svc_name' (PR #$pr_num)..."
                    if "$GCLOUD" run services delete "$svc_name" --project="$GCP_PROJECT" --region="$GCP_REGION" --quiet >/dev/null 2>&1; then
                        reaped_cloudrun=$((reaped_cloudrun + 1))
                    else
                        log "WARNING: Failed to delete Cloud Run service '$svc_name'"
                    fi
                fi
            fi
        fi
    done <<< "$services"
}

# ---------------------------------------------------------------------------
# 2. Kubernetes Preview Namespaces Reclamation
# ---------------------------------------------------------------------------
reap_k8s() {
    if ! command -v "$KUBECTL" >/dev/null 2>&1; then
        log "kubectl not found — skipping K8s namespace reap"
        return 0
    fi

    log "Scanning Kubernetes preview namespaces..."
    local namespaces
    namespaces="$("$KUBECTL" get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.creationTimestamp}{"\n"}{end}' 2>/dev/null || true)"

    while IFS=$'\t' read -r ns creation_ts; do
        [ -n "${ns:-}" ] || continue
        if is_protected "$ns"; then
            continue
        fi

        # Match namespace preview pattern: pr-<number>
        if [[ "$ns" =~ ^pr-([0-9]+)$ ]]; then
            local pr_num="${BASH_REMATCH[1]}"
            if [ -n "$ONLY_PR" ] && [ "$pr_num" != "$ONLY_PR" ]; then
                continue
            fi

            local ns_epoch=0
            if [ -n "${creation_ts:-}" ]; then
                ns_epoch="$(iso_to_epoch "$creation_ts")"
            fi

            if should_reap_pr "$pr_num" "$ns_epoch"; then
                if [ -n "$DRY_RUN" ]; then
                    log "[DRY_RUN] Would delete K8s namespace '$ns' (PR #$pr_num)"
                    reaped_k8s=$((reaped_k8s + 1))
                else
                    log "Deleting K8s namespace '$ns' (PR #$pr_num)..."
                    if "$KUBECTL" delete namespace "$ns" --timeout=60s --ignore-not-found >/dev/null 2>&1; then
                        reaped_k8s=$((reaped_k8s + 1))
                    else
                        log "WARNING: Failed to delete K8s namespace '$ns'"
                    fi
                fi
            fi
        fi
    done <<< "$namespaces"
}

# ---------------------------------------------------------------------------
# 3. Neon Postgres Copy-on-Write Database Branch Reclamation
# ---------------------------------------------------------------------------
reap_neon() {
    if [ -z "$NEON_API_KEY" ] || [ -z "$NEON_PROJECT_ID" ] || ! command -v "$CURL" >/dev/null 2>&1; then
        log "Neon credentials missing or curl not found — skipping Neon branch reap"
        return 0
    fi

    log "Scanning Neon Postgres branches for project $NEON_PROJECT_ID..."
    local response
    response="$("$CURL" -s -H "Authorization: Bearer $NEON_API_KEY" "https://console.neon.tech/api/v2/projects/${NEON_PROJECT_ID}/branches" 2>/dev/null || true)"

    local branches_tsv
    branches_tsv="$(python3 -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
    branches = data.get("branches", [])
    for b in branches:
        b_id = b.get("id", "")
        b_name = b.get("name", "")
        b_created = b.get("created_at", "")
        b_prim = b.get("primary", False)
        print(f"{b_id}\t{b_name}\t{b_created}\t{b_prim}")
except Exception:
    pass
' "$response" 2>/dev/null || true)"

    while IFS=$'\t' read -r branch_id branch_name created_at is_primary; do
        [ -n "${branch_id:-}" ] || continue
        if [ "$is_primary" = "True" ] || [ "$is_primary" = "true" ] || is_protected "$branch_name"; then
            continue
        fi

        # Match branch pattern: *-pr-<number> or pr-<number>
        if [[ "$branch_name" =~ pr-([0-9]+) ]]; then
            local pr_num="${BASH_REMATCH[1]}"
            if [ -n "$ONLY_PR" ] && [ "$pr_num" != "$ONLY_PR" ]; then
                continue
            fi

            local branch_epoch=0
            if [ -n "${created_at:-}" ]; then
                branch_epoch="$(iso_to_epoch "$created_at")"
            fi

            if should_reap_pr "$pr_num" "$branch_epoch"; then
                if [ -n "$DRY_RUN" ]; then
                    log "[DRY_RUN] Would delete Neon branch '$branch_name' ($branch_id) (PR #$pr_num)"
                    reaped_neon=$((reaped_neon + 1))
                else
                    log "Deleting Neon branch '$branch_name' ($branch_id)..."
                    if "$CURL" -s -X DELETE -H "Authorization: Bearer $NEON_API_KEY" "https://console.neon.tech/api/v2/projects/${NEON_PROJECT_ID}/branches/${branch_id}" >/dev/null 2>&1; then
                        reaped_neon=$((reaped_neon + 1))
                    else
                        log "WARNING: Failed to delete Neon branch '$branch_name'"
                    fi
                fi
            fi
        fi
    done <<< "$branches_tsv"
}

# Run all reapers
reap_cloudrun
reap_k8s
reap_neon

total_reaped=$((reaped_cloudrun + reaped_k8s + reaped_neon))
log "Summary: reaped $reaped_cloudrun Cloud Run services, $reaped_k8s K8s namespaces, $reaped_neon Neon branches (total $total_reaped)"

# Output exactly 4 key=value lines for $GITHUB_OUTPUT parsing
echo "reaped_cloudrun=${reaped_cloudrun}"
echo "reaped_k8s=${reaped_k8s}"
echo "reaped_neon=${reaped_neon}"
echo "total_reaped=${total_reaped}"
