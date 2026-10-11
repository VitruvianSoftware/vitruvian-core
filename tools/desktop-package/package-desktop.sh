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

# package-desktop.sh — Standardized release artifact packager for macOS desktop apps.
#
# Implements the standardized 6-point release artifact contract across desktop apps:
#   1. Universal DMG (<App>-<version>-universal.dmg) [+ <App>-<version>.dmg alias]
#   2. Apple Silicon DMG (<App>-<version>-arm64.dmg)
#   3. Intel x86_64 DMG (<App>-<version>-x86_64.dmg)
#   4. Universal ZIP (<App>-<version>-universal.zip)
#   5. Homebrew Cask formula in VitruvianSoftware/homebrew-tap (Casks/<app>.rb)
#   6. Sync to downloads catalog in apps/web/vitruviansoftware-dev/_data/downloads.yml
#
# Can be run directly by CI workflows, local developers, or coding agents, or
# sourced as a shell library (PACKAGE_DESKTOP_LIB_ONLY=1) for unit testing.

set -euo pipefail

# ------------------------------------------------------------------------------
# Pure Helpers (Hermetic and unit-testable without macOS toolchain)
# ------------------------------------------------------------------------------

clean_version() {
  local raw="${1:-}"
  # Extract semantic version (e.g. 1.20.1 from nexus-agent-1.20.1, home-speaker-v1.11.0, or v2.0.4)
  if [[ "$raw" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9.-]+)?) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    local ver="${raw##*-v}"
    ver="${ver#v}"
    printf '%s\n' "$ver"
  fi
}

cask_name_for_app() {
  local name="${1:-}"
  # Convert PascalCase / CamelCase to kebab-case
  # e.g. HomeSpeaker -> home-speaker, NexusAgent -> nexus-agent, Vitruvian -> vitruvian
  echo "$name" | sed -E 's/([A-Z]+)([A-Z][a-z])/\1-\2/g' | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]'
}

generate_cask_ruby() {
  local cask_name="${1:?cask name required}"
  local version="${2:?version required}"
  local sha256="${3:-}"
  local download_url="${4:?download url required}"
  local app_name="${5:?app name required}"
  local desc="${6:-macOS desktop application}"
  local homepage="${7:-https://github.com/VitruvianSoftware/vitruvian-core}"

  cat <<EOF
cask "${cask_name}" do
  version "${version}"
  sha256 "${sha256}"

  url "${download_url}"
  name "${app_name}"
  desc "${desc}"
  homepage "${homepage}"

  app "${app_name}.app"
end
EOF
}

expected_artifact_names() {
  local app_name="${1:?app name required}"
  local version="${2:?version required}"
  printf '%s-%s-universal.dmg\n' "$app_name" "$version"
  printf '%s-%s-arm64.dmg\n' "$app_name" "$version"
  printf '%s-%s-x86_64.dmg\n' "$app_name" "$version"
  printf '%s-%s-universal.zip\n' "$app_name" "$version"
  printf '%s-%s.dmg\n' "$app_name" "$version"
}

# If sourced by unit tests, stop here and expose pure functions
if [[ "${PACKAGE_DESKTOP_LIB_ONLY:-}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

# ------------------------------------------------------------------------------
# Operational Helpers (Requires macOS tools: lipo, hdiutil, ditto, codesign)
# ------------------------------------------------------------------------------

find_macho_binaries() {
  local bundle_path="${1:?bundle path required}"
  if [[ ! -d "$bundle_path" ]]; then
    return 0
  fi
  # Use -depth to traverse inside-out so nested libraries are signed before outer containers
  find "$bundle_path" -depth -type f 2>/dev/null | while IFS= read -r f; do
    if file -b "$f" 2>/dev/null | grep -qE "Mach-O"; then
      printf '%s\n' "$f"
    fi
  done
}

thin_bundle() {
  local bundle_path="${1:?bundle path required}"
  local arch="${2:?arch required (arm64|x86_64)}"
  echo "==> Thinning ${bundle_path} to ${arch}..."
  while IFS= read -r bin; do
    if lipo -info "$bin" 2>/dev/null | grep -q "$arch"; then
      # Only thin if the binary currently contains multiple architectures
      if lipo -info "$bin" 2>/dev/null | grep -qE "(arm64.*x86_64|x86_64.*arm64)"; then
        lipo "$bin" -thin "$arch" -output "$bin"
        echo "    Thinned: $(basename "$bin") -> ${arch}"
      fi
    fi
  done < <(find_macho_binaries "$bundle_path")
}

sign_bundle() {
  local bundle_path="${1:?bundle path required}"
  local entitlements="${2:-}"
  local identity="${SIGNING_IDENTITY:-}"

  if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning 2>/dev/null \
      | grep 'Developer ID Application' \
      | head -1 \
      | sed -E 's/.*"(.*)".*/\1/' || true)"
  fi

  # Bazel or unpacked outputs may be read-only and have quarantine bits
  chmod -R u+w "$bundle_path" 2>/dev/null || true
  find "$bundle_path" -exec xattr -c {} + 2>/dev/null || true

  # Sign nested components from the inside out
  while IFS= read -r bin; do
    if [[ "$bin" != *"/MacOS/"* ]]; then
      if [[ -n "$identity" ]]; then
        codesign --force --options runtime --timestamp --sign "$identity" "$bin"
      else
        codesign --force --sign - "$bin"
      fi
    fi
  done < <(find_macho_binaries "$bundle_path")

  local ent_arg=()
  if [[ -n "$entitlements" && -f "$entitlements" ]]; then
    ent_arg=(--entitlements "$entitlements")
  fi

  if [[ -n "$identity" ]]; then
    echo "==> Signing ${bundle_path} with Developer ID: ${identity}"
    codesign --force --options runtime --timestamp "${ent_arg[@]}" --sign "$identity" "$bundle_path"
  else
    echo "==> No Developer ID found; signing ad-hoc: ${bundle_path}"
    codesign --force "${ent_arg[@]}" --sign - "$bundle_path"
  fi

  codesign --verify --deep --strict "$bundle_path"
}

notarize_target() {
  local target_path="${1:?target path required}"

  if [[ -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" && (-n "${NOTARY_API_KEY_P8:-}" || -n "${NOTARY_KEY_FILE:-}") ]]; then
    local key_file="${NOTARY_KEY_FILE:-}"
    local tmp_key=""
    if [[ -z "$key_file" && -n "${NOTARY_API_KEY_P8:-}" ]]; then
      tmp_key="$(mktemp)"
      printf '%s\n' "$NOTARY_API_KEY_P8" > "$tmp_key"
      key_file="$tmp_key"
    fi

    echo "==> Submitting ${target_path} for notarization..."
    xcrun notarytool submit "$target_path" \
      --key "$key_file" \
      --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER_ID" \
      --wait

    if [[ "$target_path" == *.app || "$target_path" == *.dmg ]]; then
      echo "==> Stapling notarization ticket to ${target_path}..."
      xcrun stapler staple "$target_path"
    fi

    if [[ -n "$tmp_key" ]]; then
      rm -f "$tmp_key"
    fi
  else
    echo "==> Notary credentials not provided; skipping notarization."
  fi
}

create_dmg() {
  local app_path="${1:?app path required}"
  local out_dmg="${2:?out dmg required}"
  local volname="${3:-App}"

  echo "==> Creating DMG: ${out_dmg} (volume: ${volname})..."
  local work stage
  work="$(mktemp -d)"
  stage="$(mktemp -d)"

  ditto "$app_path" "${stage}/$(basename "$app_path")"
  ln -s /Applications "${stage}/Applications"

  local rw="${work}/rw.dmg"
  hdiutil detach "/Volumes/${volname}" -force 2>/dev/null || true

  local created=0
  for attempt in 1 2 3; do
    if hdiutil create -volname "${volname}" -srcfolder "${stage}" -fs HFS+ -format UDRW -ov "${rw}" -quiet; then
      created=1
      break
    fi
    echo "    hdiutil create attempt $attempt failed, retrying..." >&2
    rm -f "${rw}"
    sleep 2
  done

  if [[ $created -ne 1 ]]; then
    echo "✗ Failed to create disk image at ${rw}" >&2
    rm -rf "$work" "$stage"
    return 1
  fi

  rm -f "${out_dmg}"
  hdiutil convert "${rw}" -format UDZO -imagekey zlib-level=9 -o "${out_dmg}" -quiet
  rm -rf "${work}" "${stage}"

  if [[ "${SKIP_SIGNING:-false}" != "true" ]]; then
    local identity="${SIGNING_IDENTITY:-}"
    if [[ -z "$identity" ]]; then
      identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep 'Developer ID Application' \
        | head -1 \
        | sed -E 's/.*"(.*)".*/\1/' || true)"
    fi
    if [[ -n "$identity" ]]; then
      echo "==> Signing DMG with Developer ID: ${out_dmg}"
      codesign --force --timestamp --sign "$identity" "${out_dmg}"
    fi
  fi

  notarize_target "${out_dmg}"
}

create_universal_zip() {
  local app_path="${1:?app path required}"
  local out_zip="${2:?out zip required}"
  echo "==> Packaging Universal ZIP: ${out_zip}..."
  rm -f "${out_zip}"
  ditto -c -k --keepParent "$app_path" "$out_zip"
}

# ------------------------------------------------------------------------------
# CLI Driver
# ------------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage:
  package-desktop.sh [options]

Standardized packaging script for macOS desktop applications in apps/desktop/.
Produces the full 6-point distribution contract:
  1. Universal DMG (<App>-<version>-universal.dmg)
  2. Apple Silicon DMG (<App>-<version>-arm64.dmg)
  3. Intel x86_64 DMG (<App>-<version>-x86_64.dmg)
  4. Universal ZIP (<App>-<version>-universal.zip)
  5. Homebrew Cask formula in VitruvianSoftware/homebrew-tap (Casks/<app>.rb)
  6. Sync to downloads catalog via tools/sync-downloads/sync_downloads.py

Options:
  --app-path <path>       Path to built .app bundle (e.g. dist/HomeSpeaker.app)
  --archive <path>        Path to Bazel-produced .zip archive containing .app bundle
  --app-name <name>       Application name (e.g. HomeSpeaker, Vitruvian, NexusAgent)
  --version <version>     Release version (e.g. 1.11.0). Inferred from Info.plist if omitted.
  --dist-dir <dir>        Directory to store release artifacts (default: ./dist)
  --cask-name <name>      Homebrew Cask name (default: kebab-case of app-name)
  --cask-desc <desc>      Description for Homebrew Cask formula
  --cask-homepage <url>   Homepage URL for Homebrew Cask formula
  --entitlements <path>   Path to entitlements plist file for codesigning
  --repo <owner/repo>     GitHub repository (default: VitruvianSoftware/vitruvian-core)
  --tag <tag>             GitHub Release tag (e.g. home-speaker-v1.11.0)
  --skip-signing          Skip codesigning
  --skip-dmg              Skip DMG generation (useful for testing environments)
  --skip-thinning         Skip lipo thinning (arm64/x86_64 DMGs)
  --sync-downloads        Run tools/sync-downloads/sync_downloads.py after packaging
  --dry-run               Package artifacts locally and verify; do not upload to GitHub or push to tap
  --help                  Show this help message
EOF
  exit "${1:-0}"
}

APP_PATH=""
ARCHIVE=""
APP_NAME=""
VERSION=""
DIST_DIR="dist"
CASK_NAME=""
CASK_DESC=""
CASK_HOMEPAGE=""
ENTITLEMENTS=""
REPO="${GITHUB_REPOSITORY:-VitruvianSoftware/vitruvian-core}"
TAG="${TAG:-${RELEASE_TAG:-}}"
SKIP_SIGNING=false
SKIP_DMG=false
SKIP_THINNING=false
SYNC_DOWNLOADS=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-path)
      APP_PATH="$2"
      shift 2
      ;;
    --archive)
      ARCHIVE="$2"
      shift 2
      ;;
    --app-name)
      APP_NAME="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --dist-dir)
      DIST_DIR="$2"
      shift 2
      ;;
    --cask-name)
      CASK_NAME="$2"
      shift 2
      ;;
    --cask-desc)
      CASK_DESC="$2"
      shift 2
      ;;
    --cask-homepage)
      CASK_HOMEPAGE="$2"
      shift 2
      ;;
    --entitlements)
      ENTITLEMENTS="$2"
      shift 2
      ;;
    --repo)
      REPO="$2"
      shift 2
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    --skip-signing)
      SKIP_SIGNING=true
      shift
      ;;
    --skip-dmg)
      SKIP_DMG=true
      shift
      ;;
    --skip-thinning)
      SKIP_THINNING=true
      shift
      ;;
    --sync-downloads)
      SYNC_DOWNLOADS=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage 1
      ;;
  esac
done

STAGE_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

# 1. Unpack or stage input app
if [[ -n "$ARCHIVE" && -f "$ARCHIVE" ]]; then
  echo "==> Unpacking archive ${ARCHIVE} into staging..."
  ditto -x -k "$ARCHIVE" "$STAGE_ROOT"
  FOUND_APP="$(find "$STAGE_ROOT" -maxdepth 2 -name "*.app" | head -1)"
  if [[ -z "$FOUND_APP" ]]; then
    echo "✗ No .app bundle found inside archive ${ARCHIVE}" >&2
    exit 1
  fi
  APP_PATH="$FOUND_APP"
elif [[ -n "$APP_PATH" && -d "$APP_PATH" ]]; then
  echo "==> Staging application from ${APP_PATH}..."
  APP_BASENAME="$(basename "$APP_PATH")"
  ditto "$APP_PATH" "${STAGE_ROOT}/${APP_BASENAME}"
  APP_PATH="${STAGE_ROOT}/${APP_BASENAME}"
else
  echo "✗ Either --app-path or --archive must be specified and exist." >&2
  exit 1
fi

# 2. Derive metadata if missing
if [[ -z "$APP_NAME" ]]; then
  APP_NAME="$(basename "$APP_PATH" .app)"
fi

if [[ -z "$VERSION" ]]; then
  if [[ -f "${APP_PATH}/Contents/Info.plist" ]]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true)"
  fi
  if [[ -z "$VERSION" && -n "$TAG" ]]; then
    VERSION="$(clean_version "$TAG")"
  fi
  if [[ -z "$VERSION" ]]; then
    echo "✗ Version could not be determined. Specify --version <ver>." >&2
    exit 1
  fi
fi

if [[ -z "$CASK_NAME" ]]; then
  CASK_NAME="$(cask_name_for_app "$APP_NAME")"
fi

if [[ -z "$CASK_DESC" ]]; then
  CASK_DESC="macOS desktop application for ${APP_NAME}"
fi

if [[ -z "$CASK_HOMEPAGE" ]]; then
  CASK_HOMEPAGE="https://github.com/${REPO}/tree/main/apps/desktop/${CASK_NAME}"
fi

echo "================================================================================"
echo " Packaging Desktop App: ${APP_NAME}"
echo " Version:               ${VERSION}"
echo " Cask:                  ${CASK_NAME}"
echo " Dist Directory:        ${DIST_DIR}"
echo " GitHub Tag:            ${TAG:-<none>}"
echo "================================================================================"

mkdir -p "$DIST_DIR"

STAGE_UNIV="${STAGE_ROOT}/universal/${APP_NAME}.app"
mkdir -p "$(dirname "$STAGE_UNIV")"
ditto "$APP_PATH" "$STAGE_UNIV"

# 3. Codesign Universal Bundle
if [[ "$SKIP_SIGNING" != "true" ]]; then
  sign_bundle "$STAGE_UNIV" "$ENTITLEMENTS"
  notarize_target "$STAGE_UNIV"
fi

UNIVERSAL_DMG="${DIST_DIR}/${APP_NAME}-${VERSION}-universal.dmg"
LEGACY_DMG="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
ARM64_DMG="${DIST_DIR}/${APP_NAME}-${VERSION}-arm64.dmg"
X86_64_DMG="${DIST_DIR}/${APP_NAME}-${VERSION}-x86_64.dmg"
UNIVERSAL_ZIP="${DIST_DIR}/${APP_NAME}-${VERSION}-universal.zip"

# 4. Universal DMG & ZIP
if [[ "$SKIP_DMG" != "true" ]]; then
  create_dmg "$STAGE_UNIV" "$UNIVERSAL_DMG" "$APP_NAME"
  cp -f "$UNIVERSAL_DMG" "$LEGACY_DMG"
fi
create_universal_zip "$STAGE_UNIV" "$UNIVERSAL_ZIP"
cp -f "$UNIVERSAL_ZIP" "${DIST_DIR}/${APP_NAME}-${VERSION}-macOS.zip"

# 5. Architecture Thinning: Apple Silicon (arm64) & Intel (x86_64)
if [[ "$SKIP_THINNING" != "true" && "$SKIP_DMG" != "true" ]]; then
  # arm64
  STAGE_ARM64="${STAGE_ROOT}/arm64/${APP_NAME}.app"
  mkdir -p "$(dirname "$STAGE_ARM64")"
  ditto "$STAGE_UNIV" "$STAGE_ARM64"
  thin_bundle "$STAGE_ARM64" "arm64"
  if [[ "$SKIP_SIGNING" != "true" ]]; then
    sign_bundle "$STAGE_ARM64" "$ENTITLEMENTS"
    notarize_target "$STAGE_ARM64"
  fi
  create_dmg "$STAGE_ARM64" "$ARM64_DMG" "$APP_NAME"

  # x86_64
  STAGE_X86="${STAGE_ROOT}/x86_64/${APP_NAME}.app"
  mkdir -p "$(dirname "$STAGE_X86")"
  ditto "$STAGE_UNIV" "$STAGE_X86"
  thin_bundle "$STAGE_X86" "x86_64"
  if [[ "$SKIP_SIGNING" != "true" ]]; then
    sign_bundle "$STAGE_X86" "$ENTITLEMENTS"
    notarize_target "$STAGE_X86"
  fi
  create_dmg "$STAGE_X86" "$X86_64_DMG" "$APP_NAME"
fi

# 6. Checksums
echo "==> Computing SHA256 checksums..."
for art in "$DIST_DIR/${APP_NAME}-${VERSION}"*.dmg "$DIST_DIR/${APP_NAME}-${VERSION}"*.zip; do
  if [[ -f "$art" ]]; then
    (cd "$DIST_DIR" && shasum -a 256 "$(basename "$art")" > "$(basename "$art").sha256")
    cat "${art}.sha256"
  fi
done

# 7. Generate Homebrew Cask
UNIVERSAL_SHA=""
if [[ -f "$UNIVERSAL_DMG" ]]; then
  UNIVERSAL_SHA="$(shasum -a 256 "$UNIVERSAL_DMG" | cut -d' ' -f1)"
elif [[ -f "$UNIVERSAL_ZIP" ]]; then
  UNIVERSAL_SHA="$(shasum -a 256 "$UNIVERSAL_ZIP" | cut -d' ' -f1)"
fi

EFFECTIVE_TAG="${TAG:-${CASK_NAME}-v${VERSION}}"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${EFFECTIVE_TAG}/${APP_NAME}-${VERSION}-universal.dmg"
CASK_CONTENT="$(generate_cask_ruby "$CASK_NAME" "$VERSION" "$UNIVERSAL_SHA" "$DOWNLOAD_URL" "$APP_NAME" "$CASK_DESC" "$CASK_HOMEPAGE")"

CASK_FILE="${DIST_DIR}/${CASK_NAME}.rb"
printf '%s\n' "$CASK_CONTENT" > "$CASK_FILE"
echo "==> Generated Homebrew Cask formula: ${CASK_FILE}"

# 8. Homebrew Tap update
if [[ "$DRY_RUN" != "true" && -n "${HOMEBREW_TAP_TOKEN:-}" ]]; then
  TAP="VitruvianSoftware/homebrew-tap"
  TAP_DIR="${STAGE_ROOT}/homebrew-tap"
  echo "==> Updating ${TAP} Casks/${CASK_NAME}.rb..."
  git clone --depth 1 "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/${TAP}.git" "$TAP_DIR"
  mkdir -p "${TAP_DIR}/Casks"
  cp "$CASK_FILE" "${TAP_DIR}/Casks/${CASK_NAME}.rb"
  git -C "$TAP_DIR" add "Casks/${CASK_NAME}.rb"
  if git -C "$TAP_DIR" diff --cached --quiet; then
    echo "    Tap already contains up-to-date ${CASK_NAME} ${VERSION}"
  else
    git -C "$TAP_DIR" -c user.name="github-actions[bot]" \
      -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
      commit -q -m "${CASK_NAME} ${VERSION}"
    git -C "$TAP_DIR" push -q origin HEAD
    echo "    ✓ ${TAP} Casks/${CASK_NAME}.rb updated to ${VERSION}"
  fi
fi

# 9. GitHub Release Upload
if [[ "$DRY_RUN" != "true" && -n "$TAG" && -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
  echo "==> Uploading artifacts to GitHub Release: ${TAG} (${REPO})..."
  for f in "$DIST_DIR/${APP_NAME}-${VERSION}"*.dmg "$DIST_DIR/${APP_NAME}-${VERSION}"*.zip "$DIST_DIR/${APP_NAME}-${VERSION}"*.sha256; do
    if [[ -f "$f" ]]; then
      echo "    Uploading $(basename "$f")..."
      gh release upload "$TAG" "$f" --repo "$REPO" --clobber
    fi
  done
fi

# 10. Downloads Catalog Sync
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${BUILD_WORKSPACE_DIRECTORY:-}"
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
fi
SYNC_SCRIPT="${REPO_ROOT}/tools/sync-downloads/sync_downloads.py"

if [[ "$SYNC_DOWNLOADS" == "true" || (-n "$TAG" && "$DRY_RUN" != "true") ]]; then
  echo "==> Synchronizing downloads catalog..."
  if [[ -f "$SYNC_SCRIPT" ]]; then
    sync_args=()
    if [[ "$DRY_RUN" == "true" ]]; then
      sync_args+=(--dry-run)
    fi
    python3 "$SYNC_SCRIPT" "${sync_args[@]}"
  else
    echo "Warning: downloads catalog sync script not found at ${SYNC_SCRIPT}" >&2
  fi
fi

echo "==> Desktop release packaging complete for ${APP_NAME} v${VERSION}."
ls -lh "$DIST_DIR/${APP_NAME}-${VERSION}"* 2>/dev/null || true
