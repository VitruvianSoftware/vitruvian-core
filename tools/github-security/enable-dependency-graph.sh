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

# enable-dependency-graph.sh — turn on the GitHub Dependency graph for this repo.
#
# WHY THIS EXISTS AS A TARGET rather than a settings click:
#   The dependency graph is the prerequisite for the `dependency-review` gate
#   (supply-chain.yaml), which blocks a PR that introduces a dependency with a
#   known advisory. It is currently OFF: the org sets
#   dependency_graph_enabled_for_new_repositories=false, so
#   /dependency-graph/sbom 404s and the action hard-errors with "Dependency
#   review is not supported on this repository".
#
#   It cannot be expressed in repo_config: pulumi-github v6.14.0 exposes
#   dependency-graph on the ORGANIZATION resource only, never per repository.
#   PATCH /repos/{owner}/{repo} silently ignores a
#   security_and_analysis[dependency_graph] field. The only working path is an
#   org-level *code security configuration* attached to the repo -- which is
#   what this does, surgically.
#
# WHAT IT CREATES:
#   A configuration named `dependency-graph-only` with dependency_graph=enabled
#   and EVERY other setting `not_set`, so repo_config/Pulumi stays the single
#   authority for secret scanning, push protection and Dependabot. Attaching a
#   broader configuration (e.g. GitHub's "recommended") would fight Pulumi.
#
#   advanced_security=enabled is the ONE unavoidable companion: the API rejects
#   a configuration that turns on any GHAS feature without it --
#     "GitHub advanced security must be enabled when any GHAS feature is set to
#      enabled (HTTP 422)"
#   It is the gate for the feature set, not a feature itself: with every actual
#   GHAS feature left `not_set`, enabling it turns nothing else on. This repo is
#   PUBLIC, where GHAS features carry no charge -- so verify visibility before
#   reusing this on a private repo, where it WOULD have billing consequences.
#
# Idempotent: re-running when the graph is already on is a no-op.
#
# Run: bazel run //tools/github-security:enable-dependency-graph

set -euo pipefail

ORG="VitruvianSoftware"
REPO="vitruvian-core"
CONFIG_NAME="dependency-graph-only"

info() { printf '\033[36m→\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
die()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || die "the GitHub CLI (gh) is required."

# --- 0. already enabled? ------------------------------------------------------
# The SBOM endpoint is the honest probe: it only answers when the graph is on.
if gh api "repos/${ORG}/${REPO}/dependency-graph/sbom" --silent >/dev/null 2>&1; then
  ok "Dependency graph is already enabled for ${ORG}/${REPO} — nothing to do."
  exit 0
fi
info "Dependency graph is OFF for ${ORG}/${REPO} (the SBOM endpoint does not answer)."

# --- 1. make sure we hold admin:org. -----------------------------------------
# Creating/attaching an org code security configuration needs admin:org, which a
# default `gh auth login` does NOT grant. Rather than telling the operator to go
# run something, prompt for the upgrade here and continue in the same breath.
scopes="$(gh api -i user 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="x-oauth-scopes"{print $2}')"
info "current token scopes: ${scopes:-<none>}"
case ",${scopes// /}," in
  *,admin:org,*) ok "admin:org already granted." ;;
  *)
    info "admin:org is required to manage an org code security configuration."
    if [ ! -t 0 ]; then
      die "no TTY to authorise with. Re-run this target from an interactive shell:
     bazel run //tools/github-security:enable-dependency-graph"
    fi
    info "requesting the extra scope now (a browser/device prompt will appear)..."
    gh auth refresh -h github.com -s admin:org ||
      die "scope upgrade declined or failed; cannot continue."
    ok "admin:org granted."
    ;;
esac

# --- 2. find or create the surgical configuration. ---------------------------
config_id="$(gh api "orgs/${ORG}/code-security/configurations" \
  --jq ".[] | select(.name==\"${CONFIG_NAME}\") | .id" 2>/dev/null | head -1 || true)"

if [ -n "${config_id}" ]; then
  ok "reusing existing configuration ${CONFIG_NAME} (id=${config_id})."
else
  info "creating configuration ${CONFIG_NAME} (dependency_graph only, everything else not_set)..."
  config_id="$(gh api -X POST "orgs/${ORG}/code-security/configurations" \
    -f name="${CONFIG_NAME}" \
    -f description='Enables ONLY the dependency graph (prerequisite for the dependency-review gate). All other settings are not_set so repo_config/Pulumi stays the authority.' \
    -f advanced_security='enabled' \
    -f dependency_graph='enabled' \
    -f dependabot_alerts='not_set' \
    -f dependabot_security_updates='not_set' \
    -f secret_scanning='not_set' \
    -f secret_scanning_push_protection='not_set' \
    -f code_scanning_default_setup='not_set' \
    -f private_vulnerability_reporting='not_set' \
    --jq '.id')" || die "could not create the configuration."
  ok "created configuration id=${config_id}."
fi

# --- 3. attach it to this repository only. -----------------------------------
repo_id="$(gh api "repos/${ORG}/${REPO}" --jq '.id')"
info "attaching configuration ${config_id} to ${REPO} (id=${repo_id})..."
gh api -X POST "orgs/${ORG}/code-security/configurations/${config_id}/attach" \
  -f scope='selected' -F "selected_repository_ids[]=${repo_id}" >/dev/null ||
  die "could not attach the configuration."

# --- 4. verify. --------------------------------------------------------------
# Attachment is asynchronous; poll the SBOM endpoint rather than declaring
# success from a 2xx on the attach call.
info "waiting for the graph to come online..."
for _ in $(seq 1 30); do
  if gh api "repos/${ORG}/${REPO}/dependency-graph/sbom" --silent >/dev/null 2>&1; then
    ok "Dependency graph is ENABLED and answering."
    echo
    echo "Next: restore the dependency-review job in .github/workflows/supply-chain.yaml"
    echo "and add \"dependency-review\" to the required-check list in"
    echo "infrastructure/pulumi/platform/repo_config/main.go. Both carry a comment"
    echo "pointing back here."
    exit 0
  fi
  sleep 5
done

die "attached, but the graph is still not answering after ~150s. Check
   https://github.com/${ORG}/${REPO}/settings/security_analysis"
