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
# ci-preflight.sh — what CI requires, and what is actually configured.
#
#   bazel run //tools/ci-preflight            # report; non-zero if required is missing
#   bazel run //tools/ci-preflight -- --list  # just the required set, no network
#
# `//:doctor` answers "can I build this repo on THIS machine" (bazel, go, node
# versions). Nothing answered the other half -- "is the REPO wired up so CI can
# actually run" -- and that half fails in a uniquely nasty way: a missing secret
# is not a compile error, it is an empty string. The workflow runs, authenticates
# with nothing, and dies somewhere further down with a message about whatever it
# failed to reach.
#
# THE REQUIRED SET IS DERIVED, NEVER HAND-MAINTAINED:
#   Every `secrets.X` / `vars.X` in .github/workflows and .github/actions IS the
#   requirement. A hand-written manifest would be a second source of truth that
#   silently rots the first time someone adds a secret to a workflow -- the exact
#   drift this is meant to detect. Add a secret reference to a workflow and it
#   shows up here on the next run, with no edit to this file.
#
# THE DEPENDABOT CHECK IS THE POINT:
#   GitHub gives Dependabot-authored PRs a SEPARATE secret store. A workflow that
#   triggers on `pull_request` and reads `secrets.X` gets the empty string on
#   every Dependabot PR unless X also exists in the Dependabot store. There is no
#   warning: the value is simply empty.
#
#   That is not a hypothetical either. It is #1164 -- `pulumi stack select` exit
#   3, "PULUMI_ACCESS_TOKEN must be set for login during non-interactive CLI
#   sessions", on a PR whose entire diff was a go.mod version bump. The check
#   costs one API call and would have named it before it was ever hit.
#
# DEGRADES, NEVER BLUFFS:
#   Without `gh`, without auth, or with a token lacking admin scope, presence
#   becomes "?" rather than a guess. An unknown is reported as unknown and never
#   counted as either satisfied or missing -- a preflight that reports green
#   because it could not look is worse than one that refuses to.
set -euo pipefail

ROOT="${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "${ROOT}"

C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_CYAN=$'\033[36m'
C_DIM=$'\033[2m'
C_RESET=$'\033[0m'
[ -t 1 ] || { C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""; C_DIM=""; C_RESET=""; }

GLYPH_OK="✓"
GLYPH_FAIL="✗"
GLYPH_WARN="⚠"
GLYPH_UNKNOWN="?"

# Provided by Actions on every run; never configured by a human, so its absence
# from the repo secret list is correct rather than a finding.
AUTO_PROVIDED=" GITHUB_TOKEN "

LIST_ONLY=0
REPO_SLUG="${GITHUB_REPOSITORY:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST_ONLY=1 ;;
    --repo) REPO_SLUG="${2:?--repo needs owner/name}"; shift ;;
    -h | --help) sed -n '21,55p' "$0"; exit 0 ;;
    *)
      printf '%s%s ci-preflight%s — unknown flag: %s\n' \
        "$C_RED" "$GLYPH_FAIL" "$C_RESET" "$1" >&2
      exit 2
      ;;
  esac
  shift
done

[ -d .github/workflows ] || {
  printf '%s%s ci-preflight%s — no .github/workflows here (cwd: %s)\n' \
    "$C_RED" "$GLYPH_FAIL" "$C_RESET" "$PWD" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 1. Derive the required set from the workflows themselves.
# ---------------------------------------------------------------------------

# A workflow "runs on PRs" when `pull_request` (or pull_request_target) appears
# as a key of the top-level `on:` block. Scraped with awk rather than a YAML
# parser for the same reason tools/conformance/check.sh does: no dependency on a
# python YAML module being importable wherever this runs.
pr_triggered() { # pr_triggered <workflow-file> -> exit 0 if PR-triggered
  awk '
    /^on:[[:space:]]*$/          { in_on = 1; next }
    /^on:[[:space:]]*\[/         { if ($0 ~ /pull_request/) { found = 1 } ; next }
    /^[^[:space:]#]/             { in_on = 0 }
    in_on && /^[[:space:]]{2}pull_request(_target)?:[[:space:]]*$/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$1"
}

refs_in() { # refs_in <kind: secrets|vars> <file...>
  grep -rhoE "$1\.[A-Z][A-Z0-9_]*" "${@:2}" 2>/dev/null |
    sed "s/^$1\.//" | sort -u
}

SOURCES=(.github/workflows)
[ -d .github/actions ] && SOURCES+=(.github/actions)

mapfile -t REQ_SECRETS < <(refs_in secrets "${SOURCES[@]}")
mapfile -t REQ_VARS < <(refs_in vars "${SOURCES[@]}")

# Secrets read by at least one PR-triggered workflow -> these are the ones the
# Dependabot store must also carry.
pr_secrets=""
for wf in .github/workflows/*.y*ml; do
  [ -f "$wf" ] || continue
  pr_triggered "$wf" || continue
  while IFS= read -r s; do
    case " ${pr_secrets} " in *" ${s} "*) ;; *) pr_secrets="${pr_secrets} ${s}" ;; esac
  done < <(refs_in secrets "$wf")
done

if [ "${LIST_ONLY}" = "1" ]; then
  printf '%s→%s required by CI (derived from %s)\n\n' \
    "$C_CYAN" "$C_RESET" "${SOURCES[*]}"
  printf '  secrets (%d):\n' "${#REQ_SECRETS[@]}"
  printf '    %s\n' "${REQ_SECRETS[@]}"
  printf '  variables (%d):\n' "${#REQ_VARS[@]}"
  printf '    %s\n' "${REQ_VARS[@]}"
  printf '\n  read by PR-triggered workflows (must also exist in the Dependabot store):\n'
  for s in ${pr_secrets}; do
    case "${AUTO_PROVIDED}" in *" ${s} "*) continue ;; esac
    printf '    %s\n' "$s"
  done
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Ask GitHub what is actually configured. Any failure here downgrades to
#    "unknown" -- it must never be mistaken for "absent".
# ---------------------------------------------------------------------------
LIVE=1
WHY_NOT_LIVE=""

if ! command -v gh >/dev/null 2>&1; then
  LIVE=0
  WHY_NOT_LIVE="gh is not installed"
elif ! gh auth status >/dev/null 2>&1; then
  LIVE=0
  WHY_NOT_LIVE="gh is not authenticated (run: gh auth login)"
fi

if [ "${LIVE}" = "1" ] && [ -z "${REPO_SLUG}" ]; then
  REPO_SLUG="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  [ -n "${REPO_SLUG}" ] || { LIVE=0; WHY_NOT_LIVE="could not resolve owner/repo (pass --repo)"; }
fi

# names_from <api-path> <jq-filter> -> newline-separated names, empty on failure.
# Reading secret/variable NAMES needs admin on the repo; a token without it 403s,
# which is an unknown, not an empty configuration.
api_names() {
  gh api --paginate "$1" --jq "$2" 2>/dev/null || true
}

REPO_SECRETS=""; REPO_VARS=""; DEPENDABOT_SECRETS=""; ENV_SECRETS=""; ENV_VARS=""
SCOPE_OK=1
if [ "${LIVE}" = "1" ]; then
  REPO_SECRETS="$(api_names "repos/${REPO_SLUG}/actions/secrets" '.secrets[].name')"
  REPO_VARS="$(api_names "repos/${REPO_SLUG}/actions/variables" '.variables[].name')"
  DEPENDABOT_SECRETS="$(api_names "repos/${REPO_SLUG}/dependabot/secrets" '.secrets[].name')"

  # Environment-scoped values satisfy a reference just as repo-scoped ones do,
  # so they must be folded in or every environment secret reads as missing.
  while IFS= read -r env; do
    [ -n "$env" ] || continue
    ENV_SECRETS="${ENV_SECRETS}
$(api_names "repos/${REPO_SLUG}/environments/${env}/secrets" '.secrets[].name')"
    ENV_VARS="${ENV_VARS}
$(api_names "repos/${REPO_SLUG}/environments/${env}/variables" '.variables[].name')"
  done < <(api_names "repos/${REPO_SLUG}/environments" '.environments[].name')

  # If every list came back empty the token almost certainly lacks admin rather
  # than the repo genuinely having nothing configured. Treat as unknown.
  if [ -z "${REPO_SECRETS}${REPO_VARS}${DEPENDABOT_SECRETS}${ENV_SECRETS}${ENV_VARS}" ]; then
    SCOPE_OK=0
    LIVE=0
    WHY_NOT_LIVE="the GitHub API returned nothing for ${REPO_SLUG} — the token likely lacks admin:repo scope"
  fi
fi

has() { # has <needle> <haystack-newline-list>
  printf '%s\n' "$2" | grep -qxF "$1"
}

# ---------------------------------------------------------------------------
# 3. Report.
# ---------------------------------------------------------------------------
missing=0
dependabot_blind=0
unknown=0

printf '%s→%s CI preflight for %s\n' \
  "$C_CYAN" "$C_RESET" "${REPO_SLUG:-<unresolved repo>}"
printf '%s  required set derived from %s%s\n\n' \
  "$C_DIM" "${SOURCES[*]}" "$C_RESET"

if [ "${LIVE}" = "0" ]; then
  printf '%s%s offline%s — %s\n' "$C_YELLOW" "$GLYPH_WARN" "$C_RESET" "${WHY_NOT_LIVE}"
  printf '%s  Listing what CI requires; presence shown as "?" (not checked).%s\n\n' \
    "$C_DIM" "$C_RESET"
fi

printf '  %-38s %-10s %s\n' "SECRET" "REPO" "DEPENDABOT"
for s in "${REQ_SECRETS[@]}"; do
  case "${AUTO_PROVIDED}" in
    *" ${s} "*)
      printf '  %-38s %s%-10s%s %s\n' "$s" "$C_DIM" "auto" "$C_RESET" "${C_DIM}(provided by Actions)${C_RESET}"
      continue
      ;;
  esac

  needs_dependabot=0
  case " ${pr_secrets} " in *" ${s} "*) needs_dependabot=1 ;; esac

  if [ "${LIVE}" = "0" ]; then
    unknown=$((unknown + 1))
    printf '  %-38s %s%-10s%s %s\n' "$s" "$C_YELLOW" "${GLYPH_UNKNOWN}" "$C_RESET" \
      "$([ "${needs_dependabot}" = 1 ] && printf '%s' "${C_YELLOW}${GLYPH_UNKNOWN} required (PR-triggered)${C_RESET}" || printf '%s' "${C_DIM}n/a${C_RESET}")"
    continue
  fi

  if has "$s" "${REPO_SECRETS}${ENV_SECRETS}"; then
    repo_cell="${C_GREEN}${GLYPH_OK}${C_RESET}"
  else
    repo_cell="${C_RED}${GLYPH_FAIL} MISSING${C_RESET}"
    missing=$((missing + 1))
  fi

  if [ "${needs_dependabot}" = "0" ]; then
    dep_cell="${C_DIM}n/a${C_RESET}"
  elif has "$s" "${DEPENDABOT_SECRETS}"; then
    dep_cell="${C_GREEN}${GLYPH_OK}${C_RESET}"
  else
    dep_cell="${C_YELLOW}${GLYPH_WARN} empty on Dependabot PRs${C_RESET}"
    dependabot_blind=$((dependabot_blind + 1))
  fi

  printf '  %-38s %-19b %b\n' "$s" "$repo_cell" "$dep_cell"
done

printf '\n  %-38s %s\n' "VARIABLE" "REPO"
for v in "${REQ_VARS[@]}"; do
  if [ "${LIVE}" = "0" ]; then
    unknown=$((unknown + 1))
    printf '  %-38s %s%s%s\n' "$v" "$C_YELLOW" "${GLYPH_UNKNOWN}" "$C_RESET"
  elif has "$v" "${REPO_VARS}${ENV_VARS}"; then
    printf '  %-38s %s%s%s\n' "$v" "$C_GREEN" "$GLYPH_OK" "$C_RESET"
  else
    printf '  %-38s %s%s MISSING%s\n' "$v" "$C_RED" "$GLYPH_FAIL" "$C_RESET"
    missing=$((missing + 1))
  fi
done

echo
if [ "${LIVE}" = "0" ]; then
  printf '%s%s ci-preflight%s — %d requirement(s) listed, presence NOT verified (%s).\n' \
    "$C_YELLOW" "$GLYPH_WARN" "$C_RESET" "${unknown}" "${WHY_NOT_LIVE}"
  # Not a failure: an unverified run is an honest "I could not look", and
  # failing here would make the target unusable offline for its listing job.
  exit 0
fi

if [ "${dependabot_blind}" -gt 0 ]; then
  printf '%s%s %d secret(s) are read by PR-triggered workflows but absent from the Dependabot store.%s\n' \
    "$C_YELLOW" "$GLYPH_WARN" "${dependabot_blind}" "$C_RESET"
  printf '   On a Dependabot PR they resolve to the EMPTY STRING, with no warning.\n'
  printf '   Add as code in infrastructure/pulumi/platform/repo_config (dependabotSecrets),\n'
  printf '   or ad hoc:  gh secret set <NAME> --app dependabot --repo %s\n\n' "${REPO_SLUG}"
fi

if [ "${missing}" -gt 0 ]; then
  printf '%s%s ci-preflight%s — %d required value(s) missing.\n' \
    "$C_RED" "$GLYPH_FAIL" "$C_RESET" "${missing}"
  exit 1
fi

printf '%s%s ci-preflight%s — every value CI references is configured' \
  "$C_GREEN" "$GLYPH_OK" "$C_RESET"
[ "${dependabot_blind}" -gt 0 ] && printf ' (%d Dependabot gap(s) above)' "${dependabot_blind}"
printf '.\n'
