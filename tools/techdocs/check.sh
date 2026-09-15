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
#
# `techdocs:check` — Validates that every mkdocs.yml in vitruvian-core compiles
# cleanly using mkdocs-techdocs-core (matching Backstage runtime environment).
#
# Invoked via `bazel run //tools/techdocs:check`.

set -euo pipefail

ROOT="${BUILD_WORKSPACE_DIRECTORY:-$PWD}"
cd "$ROOT"

C_GREEN="\033[32m"
C_RED="\033[31m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_RESET="\033[0m"

printf "%bTechDocs build verification%b — testing all mkdocs.yml sites with mkdocs-techdocs-core\n" "$C_BOLD" "$C_RESET"

MKDOCS_FILES="$( (git ls-files "*mkdocs.yml" "**/mkdocs.yml" && git ls-files --others --exclude-standard "*mkdocs.yml" "**/mkdocs.yml") 2>/dev/null | sort -u)"

if [ -z "$MKDOCS_FILES" ]; then
  printf "%b✗ No mkdocs.yml files found in repository%b\n" "$C_RED" "$C_RESET"
  exit 1
fi

TOTAL=0
PASSED=0
FAILED=0
FAIL_LOGS=""

for cfg in $MKDOCS_FILES; do
  TOTAL=$((TOTAL + 1))
  cfg_dir="$(dirname "$cfg")"
  cfg_file="$(basename "$cfg")"
  site_dir="$cfg_dir/site"

  # Clean any pre-existing site dir
  rm -rf "$site_dir"

  # Build site using uv and mkdocs-techdocs-core==1.6.1
  set +e
  BUILD_OUT="$(cd "$cfg_dir" && uv run --with mkdocs-techdocs-core==1.6.1 mkdocs build -f "$cfg_file" 2>&1)"
  STATUS=$?
  set -e

  # Clean up generated site dir immediately to prevent dirty worktree
  rm -rf "$site_dir"

  if [ $STATUS -eq 0 ]; then
    PASSED=$((PASSED + 1))
    printf "  %b✓%b %s\n" "$C_GREEN" "$C_RESET" "$cfg"
  else
    FAILED=$((FAILED + 1))
    printf "  %b✗%b %s (failed to build)\n" "$C_RED" "$C_RESET" "$cfg"
    FAIL_LOGS="${FAIL_LOGS}\n--- Failure log for $cfg ---\n${BUILD_OUT}\n"
  fi
done

echo
if [ $FAILED -gt 0 ]; then
  printf "%b%bFAIL: %d/%d TechDocs sites failed to build%b\n" "$C_BOLD" "$C_RED" "$FAILED" "$TOTAL" "$C_RESET"
  printf "%b\n" "$FAIL_LOGS"
  exit 1
else
  printf "%b%bPASS: All %d TechDocs sites built successfully with mkdocs-techdocs-core%b\n" "$C_BOLD" "$C_GREEN" "$TOTAL" "$C_RESET"
  exit 0
fi
