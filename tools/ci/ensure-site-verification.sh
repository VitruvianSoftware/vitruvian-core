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

# ensure-site-verification.sh — automated Google domain-ownership
# SELF-verification for Cloud Run DomainMappings (oauth-user-inspector custom
# domains).
#
# ARCHITECTURE — PER-ENV SELF-VERIFICATION ONLY. This script runs inside each
# env's deploy job (_deploy-cloud-run.yaml), AS THAT ENV'S OWN DEPLOY SA, right
# before the env's `pulumi up`. The CALLING identity verifies the zone for
# ITSELF via DNS-TXT (getToken -> Cloudflare TXT -> webResource.insert) and
# NEVER touches any owners list: webResource.update / owner delegation is
# deliberately absent. Delegation is a dead end here — the zone is owned by an
# external personal account whose token-verified ownership the Site
# Verification API refuses to let a service account modify AT ALL (even a
# correct union PUT that keeps every existing owner 400s "You cannot unverify
# this site owner..."). Ownership in the Site Verification service is
# per-caller, so each env's SA must verify independently; three
# google-site-verification TXT records on the zone apex (one per env SA) is
# the expected steady state.
#
# PREREQUISITE — siteverification.googleapis.com is a CONSOLE-ONLY API. It must
# be enabled BY HAND, ONCE, on EACH env's oss floating project (the calling
# SA's quota project). It CANNOT be enabled via serviceusage/IaC: even the
# project-owner SA gets HTTP 403 PreconditionFailure. Until it is enabled
# there, this script's getToken WRITE call fails with "Site Verification API
# has not been used in project <N> before or it is disabled". Enable it at:
#   https://console.cloud.google.com/apis/library/siteverification.googleapis.com?project=<PROJECT_ID>
# (The foundation project factory declares it in ActivateApis for all three
# oss floating projects so the entry converges to a no-op AFTER the manual
# enable — see gcp-projects modules/base_env/example_floating_project.go.)
#
# WHY: creating a Cloud Run DomainMapping requires the DEPLOYING principal to
# be a verified owner of the domain in Google's Site Verification service
# ("Caller is not authorized to administer the domain ... verify ownership").
# The per-env deploy SAs are headless, so the Search Console click-path is not
# an option — this script makes ownership a converged, code-managed fact.
#
# FLOW (idempotent):
#   1. Read the app's per-env Pulumi.<env>.yaml files — ONLY the calling env's
#      file when DEPLOY_ENV is set (the per-env deploy path), else all of them.
#      Every selected env with a `customDomain` contributes its
#      `cloudflareZone` (the registrable domain to verify — verifying the zone
#      apex covers all subdomains). No customDomain -> clean no-op.
#   2. For each zone: GET webResource dns://<zone>. If the calling identity is
#      already a verified owner, no-op.
#   3. Otherwise self-verify: getToken (DNS_TXT) -> additively upsert the
#      google-site-verification TXT on the zone apex via the Cloudflare API ->
#      poll public DNS -> webResource.insert. This adds a NEW token record;
#      existing google-site-verification records (other envs' SAs, the
#      external zone owner) are never touched, and ours is never deleted —
#      Google re-checks DNS periodically, so the TXT must persist for
#      ownership to persist.
#
# INPUTS (env):
#   DEPLOY_ENV               Optional; when set (e.g. "development"), only
#                            Pulumi.$DEPLOY_ENV.yaml is considered — the
#                            per-env deploy path. Unset scans every env file.
#   SITEVERIFY_ACCESS_TOKEN  OAuth2 access token bearing the
#                            https://www.googleapis.com/auth/siteverification
#                            scope (google-github-actions/auth
#                            token_format: access_token + access_token_scopes;
#                            SA impersonation supports arbitrary scopes).
#   CLOUDFLARE_API_TOKEN     Cloudflare token, Zone.Read + DNS.Edit on the zone
#                            (read at runtime from the dev floating project's
#                            Secret Manager — never a GitHub secret; same
#                            credential the Pulumi deploys use for the CNAME).
#   SITEVERIFY_QUOTA_PROJECT Optional; when set, sent as x-goog-user-project on
#                            every Site Verification call so the getToken/insert
#                            WRITE calls attribute to the caller's OWN floating
#                            project, where the foundation project factory
#                            enables siteverification.googleapis.com. REQUIRED
#                            in practice: without the API enabled on the
#                            attributed project the WRITE calls 403 ("Site
#                            Verification API has not been used in project <N>
#                            before or it is disabled"). A read-only GET fails
#                            on scope first, so it never surfaces this — hence
#                            the earlier #948 revision wrongly concluded no
#                            quota project was needed.
#   APP_DIR                  Optional; the app's Pulumi project dir.
#
# Tokens: google-site-verification values are public DNS data, not secrets.
# The OAuth and Cloudflare tokens are only ever sent as headers, never logged.

set -euo pipefail

APP_DIR="${APP_DIR:-oauth-user-inspector/infra/app}"
# Endpoint overrides exist ONLY for the hermetic test harness
# (ensure-site-verification_test.sh); CI always uses the real defaults.
SV_BASE="${SITEVERIFY_API_BASE:-https://www.googleapis.com/siteVerification/v1}"
CF_BASE="${CLOUDFLARE_API_BASE:-https://api.cloudflare.com/client/v4}"
DOH_BASE="${DOH_API_BASE:-https://dns.google}"

for tool in curl jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ensure-site-verification: $tool not found on PATH" >&2
    exit 1
  fi
done

# --- 1. Collect the calling env's zone(s) from the per-env Pulumi config -----

cfg_get() { # cfg_get <file> <key>  (flat `ns:key: value` YAML lines)
  sed -n "s/^[[:space:]]*oauth-user-inspector:$2:[[:space:]]*//p" "$1" |
    head -n1 | tr -d '"' | tr -d "'"
}

if [ -n "${DEPLOY_ENV:-}" ]; then
  env_files=("$APP_DIR/Pulumi.$DEPLOY_ENV.yaml")
  if [ ! -e "${env_files[0]}" ]; then
    echo "ensure-site-verification: ${env_files[0]} not found (DEPLOY_ENV=$DEPLOY_ENV)" >&2
    exit 1
  fi
else
  env_files=("$APP_DIR"/Pulumi.*.yaml)
fi

zones=""
for f in "${env_files[@]}"; do
  [ -e "$f" ] || continue
  dom="$(cfg_get "$f" customDomain)"
  [ -n "$dom" ] || continue
  zone="$(cfg_get "$f" cloudflareZone)"
  if [ -z "$zone" ]; then
    # Mirror the program's default (main.go: cloudflareZone defaults to
    # ipv1337.dev when unset).
    zone="ipv1337.dev"
  fi
  case " $zones " in *" $zone "*) ;; *) zones="$zones $zone" ;; esac
  echo "ensure-site-verification: $(basename "$f"): $dom -> zone $zone"
done

if [ -z "$zones" ]; then
  echo "ensure-site-verification: no customDomain configured${DEPLOY_ENV:+ for $DEPLOY_ENV} in $APP_DIR — nothing to do"
  exit 0
fi

: "${SITEVERIFY_ACCESS_TOKEN:?SITEVERIFY_ACCESS_TOKEN is required (siteverification-scoped OAuth token)}"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required (Zone.Read + DNS.Edit)}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# --- API helpers -------------------------------------------------------------

sv_call() { # sv_call <method> <url> [json-body]; body -> $workdir/resp, echoes HTTP code
  local method="$1" url="$2" body="${3:-}"
  local args=(-sS -o "$workdir/resp" -w '%{http_code}' -X "$method" \
    -H "Authorization: Bearer $SITEVERIFY_ACCESS_TOKEN" \
    -H "Content-Type: application/json")
  # Pin quota attribution to the caller's own floating project (see header) so
  # the getToken/insert WRITE calls land on the project where the API is enabled.
  if [ -n "${SITEVERIFY_QUOTA_PROJECT:-}" ]; then
    args+=(-H "x-goog-user-project: $SITEVERIFY_QUOTA_PROJECT")
  fi
  if [ -n "$body" ]; then args+=(-d "$body"); fi
  curl "${args[@]}" "$url"
}

cf_call() { # cf_call <method> <url> [json-body]; body -> $workdir/cfresp, echoes HTTP code
  local method="$1" url="$2" body="${3:-}"
  local args=(-sS -o "$workdir/cfresp" -w '%{http_code}' -X "$method" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json")
  if [ -n "$body" ]; then args+=(-d "$body"); fi
  curl "${args[@]}" "$url"
}

sv_error_summary() {
  jq -r '.error.message // "unknown error"' "$workdir/resp" 2>/dev/null || echo "unparseable error body"
}

# get_verification_token <zone>: prints the TXT record value to place.
# The discovery doc says domains use method "DNS" in getToken while insert
# commonly takes "DNS_TXT"; accept either by trying DNS_TXT first and falling
# back to DNS on a 400.
get_verification_token() {
  local zone="$1" method code token
  for method in DNS_TXT DNS; do
    code="$(sv_call POST "$SV_BASE/token" \
      "{\"site\":{\"identifier\":\"$zone\",\"type\":\"INET_DOMAIN\"},\"verificationMethod\":\"$method\"}")"
    if [ "$code" = "200" ]; then
      token="$(jq -r '.token // empty' "$workdir/resp")"
      if [ -n "$token" ]; then
        # For the DNS method the API returns the bare token; the DNS record
        # value is the google-site-verification=<token> form. Tolerate an API
        # that already returns the full record value.
        case "$token" in
          google-site-verification=*) printf '%s' "$token" ;;
          *) printf 'google-site-verification=%s' "$token" ;;
        esac
        return 0
      fi
    fi
    echo "ensure-site-verification: getToken($method) for $zone -> HTTP $code: $(sv_error_summary)" >&2
  done
  return 1
}

# ensure_cloudflare_txt <zone> <txt-value>: additive upsert of the TXT record
# on the zone apex. Existing records (other verification tokens, SPF, ...) are
# never modified or deleted.
ensure_cloudflare_txt() {
  local zone="$1" txt="$2" code zone_id have
  code="$(cf_call GET "$CF_BASE/zones?name=$zone&status=active")"
  if [ "$code" != "200" ]; then
    echo "ensure-site-verification: Cloudflare zone lookup for $zone -> HTTP $code" >&2
    return 1
  fi
  zone_id="$(jq -r '.result[0].id // empty' "$workdir/cfresp")"
  if [ -z "$zone_id" ]; then
    echo "ensure-site-verification: Cloudflare zone $zone not found (token needs Zone.Read on it)" >&2
    return 1
  fi
  code="$(cf_call GET "$CF_BASE/zones/$zone_id/dns_records?type=TXT&name=$zone&per_page=100")"
  if [ "$code" != "200" ]; then
    echo "ensure-site-verification: Cloudflare TXT list for $zone -> HTTP $code" >&2
    return 1
  fi
  # Cloudflare may return TXT content with surrounding quotes; compare unquoted.
  have="$(jq -r --arg txt "$txt" \
    '[.result[].content | gsub("^\"|\"$"; "")] | any(. == $txt)' "$workdir/cfresp")"
  if [ "$have" = "true" ]; then
    echo "ensure-site-verification: TXT already present on $zone"
    return 0
  fi
  # Cloudflare caps record comments at 100 characters (API error 9313), so keep
  # this terse; the full rationale lives in this script's header. The "do not
  # delete" is the load-bearing part — Google re-checks DNS to retain ownership.
  code="$(cf_call POST "$CF_BASE/zones/$zone_id/dns_records" \
    "$(jq -n --arg name "$zone" --arg content "$txt" \
      '{type:"TXT", name:$name, content:$content, ttl:300, comment:"google-site-verification (Cloud Run) - do not delete; see ensure-site-verification.sh"}')")"
  if [ "$code" != "200" ]; then
    echo "ensure-site-verification: Cloudflare TXT create on $zone -> HTTP $code: $(head -c 400 "$workdir/cfresp")" >&2
    return 1
  fi
  echo "ensure-site-verification: created TXT on $zone"
}

# wait_for_txt <zone> <txt-value>: poll public DNS (Google DoH — the same
# resolver family the verification service uses) until the record is visible.
wait_for_txt() {
  local zone="$1" txt="$2" i
  for i in $(seq 1 24); do
    if curl -sS "$DOH_BASE/resolve?name=$zone&type=TXT" |
      jq -e --arg txt "$txt" \
        '[.Answer[]?.data | gsub("\""; "")] | any(. == $txt)' >/dev/null; then
      echo "ensure-site-verification: TXT visible in public DNS (attempt $i)"
      return 0
    fi
    echo "ensure-site-verification: waiting for TXT propagation on $zone (attempt $i/24)..."
    sleep 10
  done
  echo "ensure-site-verification: TXT for $zone not visible after ~4min" >&2
  return 1
}

# verify_zone <zone>: make the CALLING identity a token-verified owner.
verify_zone() {
  local zone="$1" txt code method i
  txt="$(get_verification_token "$zone")" || return 1
  ensure_cloudflare_txt "$zone" "$txt" || return 1
  wait_for_txt "$zone" "$txt" || return 1
  # Google's own resolvers can lag public visibility slightly; retry insert.
  for i in $(seq 1 8); do
    for method in DNS_TXT DNS; do
      code="$(sv_call POST "$SV_BASE/webResource?verificationMethod=$method" \
        "{\"site\":{\"identifier\":\"$zone\",\"type\":\"INET_DOMAIN\"}}")"
      if [ "$code" = "200" ]; then
        echo "ensure-site-verification: $zone verified (method $method)"
        return 0
      fi
      echo "ensure-site-verification: insert($method) $zone -> HTTP $code: $(sv_error_summary) (attempt $i/8)"
    done
    sleep 30
  done
  echo "ensure-site-verification: verification insert for $zone did not succeed" >&2
  return 1
}

# --- 2-3. Converge every zone for the CALLING identity ------------------------

for zone in $zones; do
  id_enc="$(jq -rn --arg v "dns://$zone" '$v|@uri')"

  # The webResource GET is caller-scoped: 200 iff the CALLING identity is a
  # verified owner of the zone. Already an owner -> converged, nothing to do.
  code="$(sv_call GET "$SV_BASE/webResource/$id_enc")"
  if [ "$code" = "200" ]; then
    echo "ensure-site-verification: already a verified owner of $zone; no-op"
    continue
  fi

  echo "ensure-site-verification: not yet a verified owner of $zone (GET -> HTTP $code) — self-verifying"
  verify_zone "$zone"

  # Assert convergence from the API's own view: the caller must now be an
  # owner. NO owners-list write ever happens (see header — delegation is
  # deliberately absent); insert alone makes the caller a token-verified owner.
  code="$(sv_call GET "$SV_BASE/webResource/$id_enc")"
  if [ "$code" != "200" ]; then
    echo "ensure-site-verification: webResource GET for $zone still failing after insert (HTTP $code): $(sv_error_summary)" >&2
    exit 1
  fi
  echo "ensure-site-verification: $zone converged (caller is a verified owner)"
done

echo "ensure-site-verification: done"
