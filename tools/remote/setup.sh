#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Build-cache setup helper — run `bazel run //tools/remote:setup`.
#
# Presents a menu of build caches (none / local / shared bazel-remote / BuildBuddy)
# and writes your choice to user.bazelrc (git-ignored). Nothing is enabled until you
# run it. See docs/build-cache.md (and docs/remote-build.md for BuildBuddy/RBE).
set -euo pipefail

# `bazel run` executes from the runfiles dir; operate on the repo root instead.
cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Markers delimiting the block this tool manages in user.bazelrc (matched literally).
MARK_BEGIN="# >>> build cache (managed by tools/remote:setup) — do not edit by hand"
MARK_END="# <<< build cache (managed by tools/remote:setup)"

CACHE="" URL="" PROVIDER="" ENDPOINT="" HEADER_NAME="" KEY="" DO_CI=1
SECRET_NAME="BUILDBUDDY_API_KEY"

usage() {
  cat <<'USAGE'
Usage: bazel run //tools/remote:setup -- [flags]
  --cache <none|local|shared|buildbuddy>  Build cache to configure (prompted if omitted)
  --url <grpcs://host>                     Cache URL (shared bazel-remote)
  --provider <buildbuddy|custom>           RBE provider (implies --cache buildbuddy)
  --endpoint <grpcs://host>                gRPC endpoint (custom RBE provider)
  --header-name <name>                     Auth header name (default x-buildbuddy-api-key)
  --key <key>                              API key (NON-interactive/testing only; prefer the
                                           hidden prompt or the BUILDBUDDY_API_KEY env var)
  --yes                                    Accepted for non-interactive callers (no-op)
  --no-ci                                  Configure local only; skip CI secret/snippet
  --no-local-default                       Do NOT make --config=remotecache the default
                                           for plain bazel invocations (#506 opt-out)
  -h, --help                               Show this help
USAGE
}

LOCAL_DEFAULT=1

while [ $# -gt 0 ]; do
  case "$1" in
    --cache)       CACHE="${2:?}"; shift 2 ;;
    --url)         URL="${2:?}"; shift 2 ;;
    --provider)    PROVIDER="${2:?}"; shift 2 ;;
    --endpoint)    ENDPOINT="${2:?}"; shift 2 ;;
    --header-name) HEADER_NAME="${2:?}"; shift 2 ;;
    --key)         KEY="${2:?}"; shift 2 ;;
    --yes|-y)      shift ;;
    --no-ci)       DO_CI=0; shift ;;
    --no-local-default) LOCAL_DEFAULT=0; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

# Legacy callers passing RBE flags directly imply the buildbuddy choice.
if [ -z "$CACHE" ] && [ -n "$PROVIDER$ENDPOINT" ]; then
  CACHE="buildbuddy"
fi

# Remove any block this tool previously wrote to user.bazelrc (idempotent switch).
strip_managed_block() {
  [ -f user.bazelrc ] || return 0
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    $0==b {skip=1}
    skip!=1 {print}
    $0==e {skip=0}
  ' user.bazelrc >user.bazelrc.tmp && mv user.bazelrc.tmp user.bazelrc
}

ensure_user_bazelrc_ignored() {
  if [ -f .gitignore ] && ! grep -qxF "user.bazelrc" .gitignore; then
    echo "user.bazelrc" >>.gitignore
    echo "✓ Added user.bazelrc to .gitignore."
  fi
}

# --- Menu ------------------------------------------------------------------
if [ -z "$CACHE" ]; then
  cat <<'MENU'
Pick a build cache (opt-in; the default is none):
  1) none        no cache — builds run fully locally
  2) local       disk cache on THIS machine only
  3) shared      your team's self-hosted bazel-remote server (read-only)
  4) buildbuddy  BuildBuddy (cache + remote execution)
MENU
  read -r -p "Choice [1-4] (1): " choice || true
  case "${choice:-1}" in
    1) CACHE="none" ;;
    2) CACHE="local" ;;
    3) CACHE="shared" ;;
    4) CACHE="buildbuddy" ;;
    *) echo "Invalid choice: $choice" >&2; exit 2 ;;
  esac
fi

case "$CACHE" in
  none)
    strip_managed_block
    echo "✓ No build cache configured — builds run fully locally."
    echo "  Re-run 'bazel run //tools/remote:setup' anytime to pick one."
    exit 0
    ;;
  local)
    dir="${HOME}/.cache/$(basename "$PWD")-bazel-disk"
    mkdir -p "$dir"
    touch user.bazelrc
    strip_managed_block
    {
      echo "$MARK_BEGIN"
      echo "common --disk_cache=$dir"
      echo "$MARK_END"
    } >>user.bazelrc
    ensure_user_bazelrc_ignored
    echo "✓ Local disk cache enabled: $dir"
    echo "  Personal to this machine, written to user.bazelrc (git-ignored). Safe to delete the dir."
    exit 0
    ;;
  shared)
    [ -n "$URL" ] || read -r -p "bazel-remote cache URL (e.g. grpcs://cache.example.com): " URL
    [ -n "$URL" ] || { echo "A cache URL is required for the shared cache." >&2; exit 2; }
    if [ -z "$KEY" ]; then
      read -r -s -p "Auth key if the cache needs one (blank for none, input hidden): " KEY || true
      echo
    fi
    hdr=""
    if [ -n "$KEY" ]; then hdr="${HEADER_NAME:-x-api-key}"; fi
    touch user.bazelrc
    strip_managed_block
    {
      echo "$MARK_BEGIN"
      echo "common --remote_cache=$URL"
      echo "common --remote_upload_local_results=false"
      [ -n "$hdr" ] && echo "common --remote_header=$hdr=$KEY"
      echo "$MARK_END"
    } >>user.bazelrc
    ensure_user_bazelrc_ignored
    echo "✓ Shared cache enabled (read-only): $URL"
    echo "  Written to user.bazelrc (git-ignored). If it is ever unreachable, builds fall back to local."
    echo "  CI should WRITE to it: add '--remote_cache=$URL' (+ a write credential) to the CI bazel step."
    exit 0
    ;;
  buildbuddy)
    strip_managed_block # clear any prior local/shared selection
    ;;
  *)
    echo "unknown cache: $CACHE (use none|local|shared|buildbuddy)" >&2
    exit 2
    ;;
esac

# === BuildBuddy / Remote Build Execution (RBE): cache + remote execution ===

# --- Provider --------------------------------------------------------------
if [ -z "$PROVIDER" ]; then
  read -r -p "RBE provider [buildbuddy/custom] (buildbuddy): " PROVIDER || true
  PROVIDER="${PROVIDER:-buildbuddy}"
fi
BES_RESULTS=""
case "$PROVIDER" in
  buildbuddy)
    ENDPOINT="grpcs://remote.buildbuddy.io"
    BES_RESULTS="https://app.buildbuddy.io/invocation/"
    HEADER_NAME="${HEADER_NAME:-x-buildbuddy-api-key}"
    ;;
  custom)
    [ -n "$ENDPOINT" ]    || read -r -p "gRPC endpoint (e.g. grpcs://your.rbe.host): " ENDPOINT
    [ -n "$HEADER_NAME" ] || read -r -p "Auth header name (e.g. x-api-key): " HEADER_NAME
    [ -n "$ENDPOINT" ] || { echo "An endpoint is required for a custom provider." >&2; exit 2; }
    ;;
  *) echo "unknown provider: $PROVIDER (use buildbuddy|custom)" >&2; exit 2 ;;
esac

# --- API key (never echoed/logged) -----------------------------------------
if [ -z "$KEY" ]; then
  if [ -n "${BUILDBUDDY_API_KEY:-}" ]; then
    KEY="$BUILDBUDDY_API_KEY"
  else
    read -r -s -p "API key for $PROVIDER (input hidden): " KEY || true; echo
  fi
fi
[ -n "$KEY" ] || { echo "No API key provided." >&2; exit 2; }

# --- Committed, non-secret config: tools/remote.bazelrc --------------------
mkdir -p tools
{
  echo "# Remote build execution (RBE) — generated by \`bazel run //tools/remote:setup\`."
  echo "# Non-secret + committed. The API key lives in the git-ignored user.bazelrc."
  echo "# Opt in per build with \`--config=remote\` (never breaks offline/local builds)."
  echo "common:remote --remote_executor=$ENDPOINT"
  echo "common:remote --remote_cache=$ENDPOINT"
  echo "common:remote --bes_backend=$ENDPOINT"
  [ -n "$BES_RESULTS" ] && echo "common:remote --bes_results_url=$BES_RESULTS"
  echo "common:remote --remote_timeout=10m"
  echo "common:remote --jobs=50"
  echo "common:remote --remote_download_outputs=minimal"
  echo "# Default Linux execution platform/container for RBE actions. Adjust the"
  echo "# container-image to match your toolchains. NOTE: macOS targets cannot run on"
  echo "# Linux RBE — keep them local (e.g. --strategy=...=local). See docs/remote-build.md."
  echo "common:remote --remote_default_exec_properties=OSFamily=linux"
  echo "common:remote --remote_default_exec_properties=container-image=docker://gcr.io/flame-public/executor-docker-default:enterprise-v1.6.0"
} >tools/remote.bazelrc
echo "✓ Wrote tools/remote.bazelrc (commit this — it is non-secret)."

# --- Secret config: user.bazelrc (git-ignored) -----------------------------
touch user.bazelrc
# Idempotent: drop any prior header lines for this header before re-adding.
# (strip_managed_block already ran at case entry, clearing the managed block.)
grep -v -- "--remote_header=$HEADER_NAME=" user.bazelrc | grep -v -- "--bes_header=$HEADER_NAME=" >user.bazelrc.tmp || true
mv user.bazelrc.tmp user.bazelrc
{
  echo "common:remote --remote_header=$HEADER_NAME=$KEY"
  echo "common:remote --bes_header=$HEADER_NAME=$KEY"
} >>user.bazelrc
# Local-default shared cache (#506): make every plain bazel invocation on this
# machine read AND write the BuildBuddy cache (cache-only — execution stays
# local; RBE remains an explicit --config=remote). Without the default, cache
# hit rate depends on CI alone and every dev cold-builds a large polyglot
# repo. A dead/stale key degrades gracefully: Bazel treats remote-cache errors
# as warnings and the build continues locally. Opt out with
# --no-local-default; `--cache none` removes everything.
{
  echo "$MARK_BEGIN"
  if [ "$LOCAL_DEFAULT" -eq 1 ]; then
    echo "common --config=remotecache"
  fi
  echo "common:remotecache --remote_header=$HEADER_NAME=$KEY"
  echo "common:remotecache --bes_header=$HEADER_NAME=$KEY"
  echo "common:remotecache --remote_upload_local_results"
  echo "$MARK_END"
} >>user.bazelrc
echo "✓ Wrote the API key to user.bazelrc (git-ignored — do NOT commit)."
if [ "$LOCAL_DEFAULT" -eq 1 ]; then
  echo "✓ Shared cache is now the LOCAL DEFAULT (plain bazel reads + writes it; #506)."
else
  echo "  Local default skipped (--no-local-default): use --config=remotecache explicitly."
fi
ensure_user_bazelrc_ignored

# --- CI: GitHub Actions secret + workflow snippet --------------------------
if [ "$DO_CI" -eq 1 ]; then
  echo
  echo "Configuring CI (GitHub Actions)…"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if printf '%s' "$KEY" | gh secret set "$SECRET_NAME" >/dev/null 2>&1; then
      echo "✓ Set the GitHub Actions secret $SECRET_NAME on this repo."
    else
      echo "! Could not set the secret (need repo admin?). Run it yourself:"
      echo "    printf '%s' '<your-key>' | gh secret set $SECRET_NAME"
    fi
  else
    echo "! gh CLI not found or not authenticated — set the secret manually:"
    echo "    printf '%s' '<your-key>' | gh secret set $SECRET_NAME"
  fi

  # Build-step snippet for the repo's CI. The GitHub Actions secrets expression
  # below is single-quoted so bash keeps it literal (no "bad substitution").
  echo
  echo "Add this step (or these flags) to your GitHub Actions Bazel job:"
  echo "------------------------------------------------------------------"
  echo "    - name: Build/test with RBE"
  echo "      env:"
  # shellcheck disable=SC2016  # literal GitHub Actions secrets expression; must stay unexpanded in bash
  echo '        '"$SECRET_NAME"': ${{ secrets.'"$SECRET_NAME"' }}'
  echo "      run: bazel test --config=remote --remote_header=$HEADER_NAME=\$$SECRET_NAME //..."
  echo "------------------------------------------------------------------"

  # Best-effort: point out existing workflows that run Bazel and should get the flags.
  if [ -d .github/workflows ]; then
    hits=$(grep -rlE 'bazel (build|test)' .github/workflows 2>/dev/null || true)
    if [ -n "$hits" ]; then
      echo "Detected Bazel steps in these workflows — add the env + --config=remote flags to each:"
      while IFS= read -r wf; do printf '  %s\n' "$wf"; done <<<"$hits"
    fi
  fi
fi

# --- Summary ---------------------------------------------------------------
echo
echo "Done. Cache: buildbuddy — provider $PROVIDER ($ENDPOINT)."
echo "  • Local:  bazel test --config=remote //..."
echo "  • CI:     add the snippet above (secret $SECRET_NAME is set automatically when gh is available)."
echo "  • Details: docs/build-cache.md and docs/remote-build.md."
