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

# Break-glass local release PUBLISHER — for when GitHub Actions (and thus the
# mirror publish-on-version-bump workflow) is down but a release must ship.
#
# Releases normally: release-please bumps <component>/.release-please-manifest.json
# in the monorepo -> //tools/copybara/sync exports the bump to the mirror -> the
# mirror's workflow tags + publishes. This tool does ONLY the last step (publish)
# locally, for the token/git-only, cross-platform component types:
#   * pulumi-library Go modules  -> push the slash-form tag go/pkg/<name>/vX.Y.Z
#   * npm packages (mcp-slack, pulumi-library ts/packages/*) -> npm publish
# GoReleaser binaries (devx/homelab) and nexus-agent's Swift/DMG/cask are Mac-
# and toolchain-bound; those stay MANUAL (see the break-glass runbook), not here.
#
# EXPORT FIRST. This publishes what is already on the mirror. Run
#   bazel run //tools/copybara/sync -- export <component>
# to push the version-bumped code+manifest to the mirror before publishing.
#
# Default is --dry-run-safe: without --execute it only prints the plan.

set -euo pipefail

MIRROR_BASE="https://github.com/VitruvianSoftware"
NPM_TOKEN_SECRET="NPM_PUBLISH_TOKEN" # key in the sync-env-secrets store

die() {
  echo "publish-local: $*" >&2
  exit 1
}
note() { echo "publish-local: $*" >&2; }

usage() {
  cat >&2 <<'EOF'
Break-glass local release publisher (GitHub Actions down).

Usage:
  bazel run //tools/release:publish-local -- <component> [--package <name>] [--execute]

  <component>    pulumi-library | mcp-slack
  --package <n>  limit to one package (a go/pkg/<n> or ts/packages/<n>); default: all
  --execute      actually publish/push. Omit for a dry run (prints the plan only).

Publish the EXPORTED bump only -- run `bazel run //tools/copybara/sync -- export <component>` first.
GoReleaser binaries (devx, homelab) and nexus-agent are manual: see
docs/break-glass-deploy-runbook.md.
EOF
  exit "${1:-1}"
}

# --- pure, unit-tested: the Go-module tag for a package + version. The SLASH
# separator before the version is mandatory -- `go get` resolves a subdir module
# at github.com/.../go/pkg/<name> only via the tag go/pkg/<name>/vX.Y.Z. A dash
# (go/pkg/<name>-vX.Y.Z) is an "unknown revision" (the 2026-07 cloud_run bug).
go_module_tag() { printf 'go/pkg/%s/v%s\n' "$1" "$2"; }

# manifest version: .release-please-manifest.json is {"<path>": "X.Y.Z"}.
manifest_version() { jq -r 'to_entries[0].value' "$1"; }

# When sourced by the unit test, stop here -- expose the pure helpers only.
if [ "${PUBLISH_LOCAL_LIB_ONLY:-}" = "1" ]; then return 0 2>/dev/null || exit 0; fi

ROOT="${BUILD_WORKSPACE_DIRECTORY:?run via 'bazel run', not directly}"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# GitHub auth for tag push / npm-registry checks: the org-owner gh token covers
# every GitHub-side operation (tags, releases). Fail loud if gh isn't logged in.
gh_token() { gh auth token 2>/dev/null || die "not logged in to GitHub -- run 'gh auth login'"; }

# The npm publish token is the ONE credential with no GitHub equivalent. Read it
# from the sync-env-secrets store; if it isn't there yet, PROMPT for it here,
# store it, and continue -- never make the operator leave the tool to go run
# bw-push (reducing operator friction is the point). Never on argv/stdout.
npm_token() {
  local store="$ROOT/tools/sync-env-secrets/secrets" f
  for f in "$store"/*/"$NPM_TOKEN_SECRET"; do
    [ -f "$f" ] && { cat "$f"; return 0; }
  done
  note ""
  note "$NPM_TOKEN_SECRET isn't stored yet -- saving it now via the secret store (it prompts, then pulls -> writes -> pushes SAFELY, so it can't clobber your vault)."
  note "It's a @vitruviansoftware npm AUTOMATION token: npmjs.com -> the org -> Access Tokens -> Generate -> Automation."
  # Delegate to the store tool's safe set (pull-first, so a partial local store
  # never overwrites the vault). Redirect its stdout to stderr so only the token
  # (below) reaches this function's stdout, which the caller captures.
  BUILD_WORKSPACE_DIRECTORY="$ROOT" bash "$ROOT/tools/sync-env-secrets/sync-env-secrets.sh" set shared "$NPM_TOKEN_SECRET" 1>&2 \
    || die "could not save $NPM_TOKEN_SECRET. Unlock Bitwarden (bazel run //tools/sync-env-secrets:unlock) and retry -- no partial push occurred."
  cat "$store/shared/$NPM_TOKEN_SECRET"
}

# --- Go modules (pulumi-library): push the slash tag at the mirror's HEAD. -----
publish_go_modules() {
  local mirror="$MIRROR_BASE/pulumi-library.git"
  local clone="$SCRATCH/pulumi-library"
  note "cloning $mirror (shallow) to check tags + push at its HEAD"
  git clone --quiet --depth 1 "https://x-access-token:$(gh_token)@github.com/VitruvianSoftware/pulumi-library.git" "$clone" \
    || die "clone failed (does your gh token have access to VitruvianSoftware/pulumi-library?)"
  local head
  head="$(git -C "$clone" rev-parse HEAD)"
  local pkgdir name version tag
  for pkgdir in "$ROOT"/pulumi/library/go/pkg/*/; do
    name="$(basename "$pkgdir")"
    [ -f "$pkgdir/.release-please-manifest.json" ] || continue
    [ -n "$PACKAGE" ] && [ "$PACKAGE" != "$name" ] && continue
    version="$(manifest_version "$pkgdir/.release-please-manifest.json")"
    tag="$(go_module_tag "$name" "$version")"
    if git -C "$clone" ls-remote --tags "$mirror" "refs/tags/$tag" | grep -q .; then
      note "skip $tag -- already on the mirror"
      continue
    fi
    if [ -z "$EXECUTE" ]; then
      echo "DRYRUN go-tag: $tag -> ${head:0:9} (mirror HEAD)"
      continue
    fi
    note "tagging $tag at ${head:0:9} and pushing"
    git -C "$clone" tag "$tag" "$head"
    git -C "$clone" push origin "$tag"
  done
}

# --- npm (mcp-slack, pulumi-library ts/packages/*): build + publish. ----------
publish_npm_dir() {
  local dir="$1" token="$2"
  local name version private
  name="$(jq -r '.name' "$dir/package.json")"
  version="$(jq -r '.version' "$dir/package.json")"
  private="$(jq -r '.private // false' "$dir/package.json")"
  [ "$private" = "true" ] && { note "skip $name -- private:true"; return 0; }
  if npm view "$name@$version" version >/dev/null 2>&1; then
    note "skip $name@$version -- already on the registry"
    return 0
  fi
  if [ -z "$EXECUTE" ]; then
    echo "DRYRUN npm-publish: $name@$version ($dir)"
    return 0
  fi
  note "building + publishing $name@$version"
  (
    cd "$dir"
    npm install --no-audit --no-fund
    npm run build --if-present
    NODE_AUTH_TOKEN="$token" npm publish --access public
  )
}

publish_npm_component() {
  local kind="$1" # mcp-slack | pulumi-library
  local token=""
  [ -n "$EXECUTE" ] && token="$(npm_token)"
  case "$kind" in
    mcp-slack) publish_npm_dir "$ROOT/mcp-slack" "$token" ;;
    pulumi-library)
      local d
      for d in "$ROOT"/pulumi/library/ts/packages/*/; do
        [ -f "$d/package.json" ] || continue
        [ -n "$PACKAGE" ] && [ "$PACKAGE" != "$(basename "$d")" ] && continue
        publish_npm_dir "$d" "$token"
      done
      ;;
  esac
}

main() {
  COMPONENT="" PACKAGE="" EXECUTE=""
  [ "$#" -gt 0 ] || usage 1
  COMPONENT="$1"
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --package) PACKAGE="${2:-}"; shift 2 ;;
      --execute) EXECUTE=1; shift ;;
      -h | --help) usage 0 ;;
      *) die "unknown argument '$1'" ;;
    esac
  done
  [ -z "$EXECUTE" ] && note "DRY RUN (pass --execute to publish). Run 'copybara sync export $COMPONENT' first."
  case "$COMPONENT" in
    pulumi-library)
      publish_go_modules
      publish_npm_component pulumi-library
      ;;
    mcp-slack) publish_npm_component mcp-slack ;;
    *) die "unknown component '$COMPONENT' (expected: pulumi-library | mcp-slack)" ;;
  esac
  note "done ($([ -n "$EXECUTE" ] && echo published || echo dry-run))."
}

main "$@"
