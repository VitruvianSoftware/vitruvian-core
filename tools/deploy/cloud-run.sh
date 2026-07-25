#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Blue-green Cloud Run deploy SEQUENCER — the single source of truth for the
# candidate -> smoke -> promote rollout, runnable identically from a workstation
# (`bazel run //tools/deploy:cloud-run -- ...`) and from CI. It is a faithful
# port of the inline orchestration in .github/workflows/_deploy-cloud-run.yaml
# (the "Deploy / Smoke / Shift traffic" steps), so an Actions outage never blocks
# a deploy: the operator runs the SAME logic locally (ops-as-bazel-targets).
#
# The actual `pulumi up` runs through //tools/pulumi:pulumi_cmd.sh, so GCP
# identity, GOWORK, and the Pulumi backend are resolved exactly as they are for
# `bazel run //<app>/infra/app:up`. Auth (WIF in CI, the pinned human identity
# locally) lives entirely in that wrapper — this sequencer is auth-agnostic.
#
# Per-invocation state passes to the Pulumi program via <PREFIX>_ env vars
# (NOT `pulumi config set` — the #499 de-race), and the smoke step refuses to
# fall back to the live/stable URL on a non-first deploy (the #808 false-green).
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: bazel run //tools/deploy:cloud-run -- \
  --pulumi-dir <dir> --service <name> --env <stack> --env-prefix <PREFIX> \
  --project <gcp-project> --region <region> \
  (--image-digest <ref@sha256:..> | --image-tag <tag>) \
  [--smoke-path /health] [--custom-smoke-script '<sh>'] [--refresh] \
  [--stable-revision <rev>] [--phase all|candidate|smoke|promote] [--dry-run]
EOF
  exit 2
}

# The <PREFIX>_IMAGE_* assignment the Pulumi program reads (digest wins; #499).
image_env_kv() {
  if [ -n "$IMAGE_DIGEST" ]; then
    echo "${PREFIX}_IMAGE_DIGEST=${IMAGE_DIGEST}"
  else
    echo "${PREFIX}_IMAGE_TAG=${IMAGE_TAG}"
  fi
}

# PURE + unit-tested (#808): pick the URL to smoke. A resolved candidate tag URL
# always wins; on the FIRST-EVER deploy (no stable, no candidate tag) the live
# service URL IS the new revision, so smoke that; on a non-first deploy an
# unresolvable candidate must FAIL (falling back to the stable URL would
# false-green and promote an untested revision). Echoes the URL, or returns 1.
resolve_smoke_url() {
  local cand="$1" first_deploy="$2" service_url="$3"
  if [ -n "$cand" ] && [ "$cand" != "null" ]; then
    echo "$cand"; return 0
  fi
  if [ "$first_deploy" = "true" ]; then
    echo "$service_url"; return 0
  fi
  echo "cloud-run: could not resolve the candidate revision URL on a non-first deploy. Refusing to smoke the stable revision (that would false-green and promote an untested revision, #808). Failing." >&2
  return 1
}

# Invoke the shared pulumi wrapper for THIS app's project dir. Extra args are
# forwarded to pulumi verbatim. Honors --dry-run (prints instead of running).
pulumi_wrap() {
  if [ -n "$DRY_RUN" ]; then
    echo "DRYRUN pulumi: (dir=$PULUMI_DIR) pulumi $*"
    return 0
  fi
  local wrap="${BUILD_WORKSPACE_DIRECTORY:?cloud-run must be invoked via 'bazel run'}/tools/pulumi/pulumi_cmd.sh"
  bash "$wrap" "$PULUMI_DIR" "$@"
}

deploy_phase() { # $1 = promote (true|false)
  local promote="$1" refresh=""
  # --refresh reconciles Pulumi state against the live cloud before the 0%-traffic
  # candidate up (so e.g. a resource deleted to force a rebuild is seen as gone and
  # recreated). The promote is a second up of the SAME program seconds later, with
  # state already reconciled by the candidate up -- so it NEVER refreshes. This
  # matches _deploy-cloud-run.yaml's inline behavior (candidate `up --refresh`,
  # promote plain `up`).
  [ "$promote" = false ] && refresh="$REFRESH"
  export "$(image_env_kv)"
  export "${PREFIX}_STABLE_REVISION=${STABLE}"
  export "${PREFIX}_PROMOTE=${promote}"
  echo "cloud-run: [$([ "$promote" = true ] && echo promote || echo candidate)] ${PREFIX}_PROMOTE=${promote} ${PREFIX}_STABLE_REVISION=${STABLE:-<empty>}" >&2
  # shellcheck disable=SC2086  # refresh must expand to nothing when empty
  pulumi_wrap up --stack "$ENV" --yes ${refresh}
}

smoke_phase() {
  local cand="" service_url="" url
  if [ -n "$DRY_RUN" ]; then
    echo "DRYRUN smoke: resolve candidate URL for ${SVC}, then GET <url>${SMOKE_PATH} (first_deploy=${FIRST_DEPLOY})" >&2
    return 0
  fi
  cand="$(gcloud run services describe "$SVC" --project "$PROJECT" --region "$REGION" --format=json \
    | jq -r '.status.traffic[]? | select(.tag=="candidate") | .url' | head -n1)"
  if [ "$FIRST_DEPLOY" = "true" ]; then
    service_url="$(pulumi_wrap stack output serviceUrl --stack "$ENV")"
  fi
  url="$(resolve_smoke_url "$cand" "$FIRST_DEPLOY" "$service_url")"
  if [ -n "$CUSTOM_SMOKE" ]; then
    echo "cloud-run: running custom smoke against ${url}" >&2
    CAND="$url" bash -c "$CUSTOM_SMOKE"
  else
    echo "cloud-run: smoke GET ${url}${SMOKE_PATH}" >&2
    curl --fail --retry 10 --retry-delay 5 --retry-connrefused "${url}${SMOKE_PATH}"
  fi
}

main() {
  PULUMI_DIR= SERVICE= ENV= PREFIX= PROJECT= REGION=
  IMAGE_DIGEST= IMAGE_TAG= SMOKE_PATH=/ CUSTOM_SMOKE= REFRESH= STABLE_OVERRIDE=
  PHASE=all DRY_RUN=

  while [ $# -gt 0 ]; do
    case "$1" in
      --pulumi-dir) PULUMI_DIR="${2:-}"; shift 2 ;;
      --service) SERVICE="${2:-}"; shift 2 ;;
      --env) ENV="${2:-}"; shift 2 ;;
      --env-prefix) PREFIX="${2:-}"; shift 2 ;;
      --project) PROJECT="${2:-}"; shift 2 ;;
      --region) REGION="${2:-}"; shift 2 ;;
      --image-digest) IMAGE_DIGEST="${2:-}"; shift 2 ;;
      --image-tag) IMAGE_TAG="${2:-}"; shift 2 ;;
      --smoke-path) SMOKE_PATH="${2:-}"; shift 2 ;;
      --custom-smoke-script) CUSTOM_SMOKE="${2:-}"; shift 2 ;;
      # A workspace-relative path to a smoke script (read from the source tree,
      # same as the pulumi wrapper above). Preferred over --custom-smoke-script
      # for a multi-line script: an sh_binary `args`-baked multi-line string is
      # word-split by the bazel-run launcher, whereas a file path is one token.
      --custom-smoke-script-file)
        CUSTOM_SMOKE="$(cat "${BUILD_WORKSPACE_DIRECTORY:?--custom-smoke-script-file needs bazel run}/${2:-}")"
        shift 2
        ;;
      --refresh) REFRESH="--refresh"; shift ;;
      --stable-revision) STABLE_OVERRIDE="${2:-}"; shift 2 ;;
      --phase) PHASE="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h | --help) usage ;;
      *) echo "cloud-run: unknown argument '$1'" >&2; usage ;;
    esac
  done

  for _req in PULUMI_DIR:--pulumi-dir SERVICE:--service ENV:--env PREFIX:--env-prefix PROJECT:--project REGION:--region; do
    _var="${_req%%:*}"; _flag="${_req#*:}"
    eval "_val=\${$_var}"
    [ -n "$_val" ] || { echo "cloud-run: missing required $_flag" >&2; usage; }
  done
  case "$PHASE" in all | candidate | smoke | promote) ;; *) echo "cloud-run: --phase must be all|candidate|smoke|promote" >&2; usage ;; esac
  if [ -z "$IMAGE_DIGEST" ] && [ -z "$IMAGE_TAG" ]; then
    echo "cloud-run: need --image-digest or --image-tag" >&2; usage
  fi

  SVC="${SERVICE}-${ENV}"

  # Resolve the stable (currently-serving) revision, ONCE. Empty => first-ever
  # deploy (program routes 100% straight to the new revision). --stable-revision
  # overrides the live lookup (operator knows it, or for --dry-run/tests).
  # Captured once and reused by candidate + promote so they stay consistent (#808).
  STABLE=
  if [ -n "$STABLE_OVERRIDE" ]; then
    STABLE="$STABLE_OVERRIDE"
  elif [ -z "$DRY_RUN" ]; then
    STABLE="$(gcloud run services describe "$SVC" --project "$PROJECT" --region "$REGION" \
      --format='value(status.traffic[0].revisionName)' 2>/dev/null || true)"
  fi
  FIRST_DEPLOY=false
  [ -z "$STABLE" ] && FIRST_DEPLOY=true

  echo "cloud-run: service=${SVC} env=${ENV} prefix=${PREFIX} phase=${PHASE} $(image_env_kv | sed 's/=/ = /')" >&2
  echo "cloud-run: stable_revision=${STABLE:-<none, first deploy>} first_deploy=${FIRST_DEPLOY}" >&2

  case "$PHASE" in
    candidate) deploy_phase false ;;
    smoke) smoke_phase ;;
    promote) deploy_phase true ;;
    all)
      deploy_phase false
      smoke_phase
      deploy_phase true
      ;;
  esac
  echo "cloud-run: phase '${PHASE}' complete for ${SVC}." >&2
}

# Run main only when EXECUTED; stay quiet when SOURCED (so tests can exercise the
# pure functions above without running a deploy).
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  main "$@"
fi
