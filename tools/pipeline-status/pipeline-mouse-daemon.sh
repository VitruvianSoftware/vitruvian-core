#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# pipeline-mouse-daemon — Monitors GitHub main branch and updates the GravaStar mouse RGB indicator.
#
# LED State Matrix:
#   - Pulsing Yellow: Pipeline is in-progress and all running checks are green so far.
#   - Pulsing Red:    A check has failed, but there are still more checks running in-flight.
#   - Solid Red:      Pipeline has completed and at least 1 check failed.
#   - Solid Green:    Pipeline has completed and all checks passed.
#
set -uo pipefail

INTERVAL="${POLL_INTERVAL:-15}"
REPO="${PIPELINE_REPO:-VitruvianSoftware/vitruvian-core}"
BRANCH="${PIPELINE_BRANCH:-main}"

# Resolve real path in case this script was invoked through a symlink
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PIPELINE_CMD="$SCRIPT_DIR/pipeline-status.sh"

GRAVASTAR_BIN="${GRAVASTAR_BIN:-}"
if [ -z "$GRAVASTAR_BIN" ]; then
  if command -v gravastar-mouse >/dev/null 2>&1; then
    GRAVASTAR_BIN="gravastar-mouse"
  elif [ -x "$REPO_ROOT/bazel-bin/packages/peripherals/gravastar-mouse" ]; then
    GRAVASTAR_BIN="$REPO_ROOT/bazel-bin/packages/peripherals/gravastar-mouse"
  else
    echo "Building //packages/peripherals:gravastar-mouse..."
    (cd "$REPO_ROOT" && bazel build --config=macos-app //packages/peripherals:gravastar-mouse)
    GRAVASTAR_BIN="$REPO_ROOT/bazel-bin/packages/peripherals/gravastar-mouse"
  fi
fi

cleanup() {
  echo ""
  echo "Stopping daemon. Restoring original mouse lighting baseline..."
  "$GRAVASTAR_BIN" restore || true
  exit 0
}

trap cleanup SIGINT SIGTERM

echo "=== GravaStar Main Branch CI Status Daemon ==="
echo "Repo:     $REPO"
echo "Branch:   $BRANCH"
echo "Interval: ${INTERVAL}s"
echo "Mouse:    $GRAVASTAR_BIN"
echo "LED Matrix:"
echo "  • Pulsing Yellow: in-progress (no failures so far)"
echo "  • Pulsing Red:    early failure (failed check, more still running)"
echo "  • Solid Red:      pipeline completed with failure"
echo "  • Solid Green:    pipeline completed with all green"
echo "Press Ctrl+C to stop and restore baseline lighting."
echo ""

LAST_SIGNAL=""
LAST_SHA=""

while true; do
  TARGET_SHA=$(gh api "repos/${REPO}/commits/${BRANCH}" --jq '.sha' 2>/dev/null || git rev-parse "origin/${BRANCH}" 2>/dev/null || echo "HEAD")

  set +e
  PIPELINE_REPO="$REPO" "$PIPELINE_CMD" "$TARGET_SHA" >/tmp/pipeline-status-out.txt 2>&1
  rc=$?
  set -u

  FAILED_COUNT=$(grep -o -E '[0-9]+ failed' /tmp/pipeline-status-out.txt 2>/dev/null | head -n 1 | awk '{print $1}')
  IN_FLIGHT_COUNT=$(grep -o -E '[0-9]+ in-flight' /tmp/pipeline-status-out.txt 2>/dev/null | head -n 1 | awk '{print $1}')
  FAILED_COUNT="${FAILED_COUNT:-0}"
  IN_FLIGHT_COUNT="${IN_FLIGHT_COUNT:-0}"

  SIGNAL=""
  if [ "$FAILED_COUNT" -gt 0 ] && [ "$IN_FLIGHT_COUNT" -gt 0 ]; then
    # Early failure: Check failed while others are still running -> PULSING RED
    SIGNAL="pulsing_red"
  elif [ "$FAILED_COUNT" -gt 0 ] && [ "$IN_FLIGHT_COUNT" -eq 0 ]; then
    # Pipeline completed and at least 1 check failed -> SOLID RED
    SIGNAL="solid_red"
  elif [ "$IN_FLIGHT_COUNT" -gt 0 ]; then
    # Pipeline running and all checks green so far -> PULSING YELLOW
    SIGNAL="pulsing_yellow"
  elif [ "$rc" -eq 0 ]; then
    # Pipeline completed successfully -> SOLID GREEN
    SIGNAL="solid_green"
  else
    SIGNAL="warning"
  fi

  SUMMARY=$(head -n 2 /tmp/pipeline-status-out.txt | tail -n 1)

  if [ "$SIGNAL" != "$LAST_SIGNAL" ] || [ "$TARGET_SHA" != "$LAST_SHA" ]; then
    echo "[$(date '+%H:%M:%S')] Commit: ${TARGET_SHA:0:8} | Status transition: '${LAST_SIGNAL:-none}' -> '$SIGNAL'"
    echo "  $SUMMARY"
    case "$SIGNAL" in
      pulsing_red)
        # Pulsing Red: Check failed, but other checks still in-flight
        "$GRAVASTAR_BIN" breathe red --speed 7 --brightness 9
        ;;
      solid_red)
        # Solid Red: Pipeline finished and >= 1 check failed
        "$GRAVASTAR_BIN" color red --brightness 7
        ;;
      pulsing_yellow)
        # Pulsing Yellow: Pipeline in-flight, no failures
        "$GRAVASTAR_BIN" breathe yellow --speed 5 --brightness 7
        ;;
      solid_green)
        # Solid Green: Pipeline finished all passing
        "$GRAVASTAR_BIN" signal success
        ;;
      *)
        "$GRAVASTAR_BIN" signal warning
        ;;
    esac
    LAST_SIGNAL="$SIGNAL"
    LAST_SHA="$TARGET_SHA"
  else
    printf "[%s] Commit: %s | Status steady: %s\n" "$(date '+%H:%M:%S')" "${TARGET_SHA:0:8}" "$SIGNAL"
  fi

  sleep "$INTERVAL"
done
