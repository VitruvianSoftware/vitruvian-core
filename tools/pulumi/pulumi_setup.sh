#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Guided Pulumi bootstrap — invoked via `bazel run //<project>:setup`.
#
# The calling `sh_binary` bakes in the project dir via `args = [<dir>]`:
#   $1  workspace-relative path to the Pulumi project directory
#
# This is a pragmatic, idempotent helper — not magic. It checks prerequisites,
# logs you in, helps pick or create a stack, and prints the one-time adoption
# hint. Re-running it is safe.
set -euo pipefail

PROJECT_DIR="${1:?usage: bazel run //<pulumi-project>:setup (dir is baked in by the macro)}"
shift || true

# `bazel run` executes from the runfiles dir; operate on the project dir instead.
cd "${BUILD_WORKSPACE_DIRECTORY:?this target must be invoked via 'bazel run', not 'bazel test'}/$PROJECT_DIR"

echo "Pulumi setup for $PROJECT_DIR"
echo "----------------------------------------------------------------------"

# --- Prerequisites ---------------------------------------------------------
missing=0
if ! command -v pulumi >/dev/null 2>&1; then
  echo "! pulumi CLI not found. Install it: https://www.pulumi.com/docs/install/" >&2
  missing=1
fi
if ! command -v go >/dev/null 2>&1; then
  echo "! go toolchain not found. Install Go: https://go.dev/dl/ (Pulumi compiles the program with it)." >&2
  missing=1
fi
if [ "$missing" -ne 0 ]; then
  echo "Install the missing tool(s) above and re-run this command." >&2
  exit 1
fi
echo "✓ pulumi and go are installed."

# --- Make the standalone module build-ready --------------------------------
# These Pulumi modules are standalone Go modules (own go.mod), deliberately kept
# out of any repo-level go.work. Disable workspace mode so `go mod tidy` (and the
# `go build` Pulumi runs later) resolve from THIS module — otherwise, inside a
# monorepo with a go.work, they fail with "not a known dependency".
export GOWORK=off
echo "Resolving Go dependencies (go mod tidy)…"
go mod tidy
echo "✓ go.sum is up to date."

# --- Login (idempotent) ----------------------------------------------------
if pulumi whoami >/dev/null 2>&1; then
  echo "✓ Already logged in to Pulumi as '$(pulumi whoami 2>/dev/null)'."
else
  echo "Logging in to Pulumi (opens a browser, or use a PULUMI_ACCESS_TOKEN / 'pulumi login --local')…"
  pulumi login
fi

# --- Stack select / create -------------------------------------------------
if pulumi stack --show-name >/dev/null 2>&1; then
  echo "✓ Stack already selected: $(pulumi stack --show-name 2>/dev/null)."
else
  echo
  echo "Available stacks:"
  pulumi stack ls 2>/dev/null || echo "  (none yet)"
  read -r -p "Stack to select or create (e.g. dev): " STACK || true
  STACK="${STACK:-dev}"
  if pulumi stack select "$STACK" >/dev/null 2>&1; then
    echo "✓ Selected existing stack '$STACK'."
  else
    pulumi stack init "$STACK"
    echo "✓ Created and selected stack '$STACK'."
  fi
fi

# --- GitHub provider token (never echoed) ----------------------------------
echo
if [ -n "${GITHUB_TOKEN:-}" ]; then
  echo "✓ GITHUB_TOKEN is set in the environment (value not shown)."
else
  echo "! GITHUB_TOKEN is NOT set. The GitHub provider needs it. Export a PAT/token"
  echo "  with repo + admin scope before running 'up' (it is read from the env, never stored here):"
  echo "      export GITHUB_TOKEN=<your-token>"
fi

# --- One-time adoption hint (repo_config) ----------------------------------
case "$PROJECT_DIR" in
  *repo_config)
    echo
    echo "Adoption note (repo_config): your repository already exists, so the first"
    echo "'up' IMPORTS it into state rather than creating it. Set the owner first:"
    echo "      bazel run //$PROJECT_DIR:config -- set repoOwner <your-org-or-user>"
    echo "then preview / apply:"
    echo "      bazel run //$PROJECT_DIR:preview"
    echo "      bazel run //$PROJECT_DIR:up"
    echo "If the import fails, fix repoName/repoOwner (and the token's account) and retry —"
    echo "no resource is created until the import resolves."

    # --- Automation opt-in (CI/CD via the shared org App) ------------------
    # Flip the two PER-REPO toggle variables the templated workflows gate on:
    #   REPO_CONFIG_PREVIEW_ENABLED  -> _repo-config-preview.yaml (preview on PRs)
    #   REPO_CONFIG_AUTO_APPLY       -> _repo-config-apply.yaml    (apply on merge)
    # The actual Pulumi App credentials are ORG-LEVEL and set once by
    # `bazel run //tools/pulumi:create-app`; we only check they exist here.
    # All prompts default to N and use '|| true' so non-interactive runs
    # (bazel test / CI) never hang.
    echo
    if ! command -v gh >/dev/null 2>&1; then
      echo "! gh CLI not found — skipping CI/CD automation opt-in. Install it"
      echo "  (https://cli.github.com/, then 'gh auth login') and re-run to enable it."
    else
      echo "CI/CD automation (optional): drive repo_config from GitHub Actions via the"
      echo "shared org Pulumi App. Set the per-repo toggles the workflows gate on."

      read -r -p "Enable Pulumi preview on pull requests? [y/N] " ENABLE_PREVIEW || true
      case "${ENABLE_PREVIEW:-N}" in
        [yY] | [yY][eE][sS])
          if gh variable set REPO_CONFIG_PREVIEW_ENABLED --body true; then
            echo "✓ REPO_CONFIG_PREVIEW_ENABLED=true (preview will run on pull requests)."
          else
            echo "! Failed to set REPO_CONFIG_PREVIEW_ENABLED (gh not authenticated, or insufficient repo perms?) — skipping." >&2
          fi
          ;;
        *)
          if gh variable set REPO_CONFIG_PREVIEW_ENABLED --body false; then
            echo "✓ REPO_CONFIG_PREVIEW_ENABLED=false (preview-on-PR disabled)."
          else
            echo "! Failed to set REPO_CONFIG_PREVIEW_ENABLED (gh not authenticated, or insufficient repo perms?) — skipping." >&2
          fi
          ;;
      esac

      read -r -p "Enable Pulumi apply on merge (auto-up)? [y/N] " ENABLE_APPLY || true
      case "${ENABLE_APPLY:-N}" in
        [yY] | [yY][eE][sS])
          if gh variable set REPO_CONFIG_AUTO_APPLY --body true; then
            echo "✓ REPO_CONFIG_AUTO_APPLY=true (merges to the default branch will 'up')."
          else
            echo "! Failed to set REPO_CONFIG_AUTO_APPLY (gh not authenticated, or insufficient repo perms?) — skipping." >&2
          fi
          ;;
        *)
          if gh variable set REPO_CONFIG_AUTO_APPLY --body false; then
            echo "✓ REPO_CONFIG_AUTO_APPLY=false (apply-on-merge disabled)."
          else
            echo "! Failed to set REPO_CONFIG_AUTO_APPLY (gh not authenticated, or insufficient repo perms?) — skipping." >&2
          fi
          ;;
      esac

      # Org-cred check (best-effort): these are set once by ':create-app' and
      # inherited by every repo. Listing org vars/secrets needs org-admin, so
      # guard with '|| true' and only print a hint when something looks missing —
      # never set per-repo creds here.
      OWNER="$(gh repo view --json owner --jq .owner.login 2>/dev/null || true)"
      if [ -n "$OWNER" ]; then
        ORG_VARS="$(gh variable list --org "$OWNER" 2>/dev/null || true)"
        ORG_SECRETS="$(gh secret list --org "$OWNER" 2>/dev/null || true)"
        if ! printf '%s' "$ORG_VARS" | grep -q 'PULUMI_APP_ID' ||
          ! printf '%s' "$ORG_SECRETS" | grep -q 'APP_PRIVATE_KEY' ||
          ! printf '%s' "$ORG_SECRETS" | grep -q 'PULUMI_ACCESS_TOKEN'; then
          echo "! Org-level Pulumi App credentials not found — run \`bazel run //tools/pulumi:create-app\` once for the org."
        else
          echo "✓ Org-level Pulumi App credentials (PULUMI_APP_ID / APP_PRIVATE_KEY / PULUMI_ACCESS_TOKEN) are present."
        fi
      else
        echo "! Could not determine the repo owner (gh not authenticated?) — skipping the"
        echo "  org-credential check. Ensure \`bazel run //tools/pulumi:create-app\` has been run for the org."
      fi

      echo "Reminder: the shared org App must be INSTALLED on this repo for token minting."
      echo "  Install it (replace <slug>, e.g. <org>-pulumi) at:"
      echo "      https://github.com/apps/<slug>/installations/new"
    fi
    ;;
  *)
    echo
    echo "Next steps:"
    echo "      bazel run //$PROJECT_DIR:preview"
    echo "      bazel run //$PROJECT_DIR:up"
    ;;
esac

echo
echo "Done. This helper is safe to re-run any time."
