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

# gate-evaluator.sh — Synthetic Status Gate Aggregator Evaluator.
# Evaluates upstream CI/presubmit job results with strict fail-closed invariants.
# Exits 0 on legitimate success/skip, exits 1 on failure/cancellation.

set -euo pipefail

ORCHESTRATE_RESULT="${ORCHESTRATE_RESULT:-unknown}"
PIPELINE_UNITS_RESULT="${PIPELINE_UNITS_RESULT:-unknown}"
LINT_NAMING_RESULT="${LINT_NAMING_RESULT:-unknown}"
LICENSE_CHECK_RESULT="${LICENSE_CHECK_RESULT:-unknown}"
GO_RACE_RESULT="${GO_RACE_RESULT:-unknown}"
DOCS_ONLY="${DOCS_ONLY:-false}"
AFFECTED_COUNT="${AFFECTED_COUNT:-0}"

echo "========================================================"
echo "          Presubmit Gate Status Aggregator              "
echo "========================================================"
echo "Orchestrator Result:    ${ORCHESTRATE_RESULT}"
echo "Pipeline Units Result:  ${PIPELINE_UNITS_RESULT} (Affected: ${AFFECTED_COUNT}, Docs-only: ${DOCS_ONLY})"
echo "Lint Naming Result:     ${LINT_NAMING_RESULT}"
echo "License Check Result:   ${LICENSE_CHECK_RESULT}"
echo "Go Race Result:         ${GO_RACE_RESULT}"
echo "========================================================"

FAILED=0

# Invariant 1: Orchestrator MUST succeed
if [ "${ORCHESTRATE_RESULT}" != "success" ]; then
  echo "::error::Orchestrator failed or was cancelled (result: ${ORCHESTRATE_RESULT})"
  FAILED=1
fi

# Invariant 2: Dynamic pipeline units must be success OR skipped (0 affected units)
case "${PIPELINE_UNITS_RESULT}" in
  success)
    echo "✓ Dynamic pipeline units passed cleanly."
    ;;
  skipped)
    if [ "${DOCS_ONLY}" = "true" ] || [ "${AFFECTED_COUNT}" -eq 0 ]; then
      echo "✓ Dynamic pipeline units skipped cleanly (0 affected units / docs-only)."
    else
      echo "::error::Dynamic pipeline units were skipped unexpectedly when ${AFFECTED_COUNT} units were affected."
      FAILED=1
    fi
    ;;
  *)
    echo "::error::Dynamic pipeline units failed or were cancelled (result: ${PIPELINE_UNITS_RESULT})"
    FAILED=1
    ;;
esac

# Invariant 3: Static invariant checks must succeed or be skipped
for check in "lint-naming:${LINT_NAMING_RESULT}" "license-check:${LICENSE_CHECK_RESULT}" "go-race:${GO_RACE_RESULT}"; do
  name="${check%%:*}"
  res="${check##*:}"
  case "$res" in
    success|skipped)
      echo "✓ ${name} check passed (${res})."
      ;;
    *)
      echo "::error::Static check '${name}' failed (result: ${res})"
      FAILED=1
      ;;
  esac
done

echo "========================================================"
if [ "${FAILED}" -ne 0 ]; then
  echo "✗ GATE VERDICT: FAILED — one or more required checks failed."
  exit 1
else
  echo "✓ GATE VERDICT: ALL REQUIRED CHECKS PASSED"
  exit 0
fi
