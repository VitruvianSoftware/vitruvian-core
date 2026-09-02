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

# Unit tests for tools/ci/gate-evaluator.sh

set -uo pipefail

EVALUATOR="$(cd "$(dirname "$0")" && pwd)/gate-evaluator.sh"
[ -f "$EVALUATOR" ] || { echo "FATAL: gate-evaluator.sh not found"; exit 1; }

FAILURES=0
CASES=0

run_test() {
  desc="$1"; expected_exit="$2"; shift 2
  CASES=$((CASES + 1))
  
  if env "$@" bash "$EVALUATOR" >/dev/null 2>&1; then
    actual_exit=0
  else
    actual_exit=1
  fi
  
  if [ "$actual_exit" -eq "$expected_exit" ]; then
    printf "PASS  %s\n" "$desc"
  else
    printf "FAIL  %s (expected exit %d, got %d)\n" "$desc" "$expected_exit" "$actual_exit"
    FAILURES=$((FAILURES + 1))
  fi
}

# 1. Normal all-green run
run_test "All jobs green passes gate" 0 \
  ORCHESTRATE_RESULT="success" \
  PIPELINE_UNITS_RESULT="success" \
  LINT_NAMING_RESULT="success" \
  LICENSE_CHECK_RESULT="success" \
  GO_RACE_RESULT="success" \
  AFFECTED_COUNT=2

# 2. Docs-only skip
run_test "Docs-only skip passes gate" 0 \
  ORCHESTRATE_RESULT="success" \
  PIPELINE_UNITS_RESULT="skipped" \
  LINT_NAMING_RESULT="success" \
  LICENSE_CHECK_RESULT="success" \
  GO_RACE_RESULT="skipped" \
  DOCS_ONLY="true" \
  AFFECTED_COUNT=0

# 3. Dynamic unit failure
run_test "Dynamic unit failure fails gate" 1 \
  ORCHESTRATE_RESULT="success" \
  PIPELINE_UNITS_RESULT="failure" \
  LINT_NAMING_RESULT="success" \
  LICENSE_CHECK_RESULT="success" \
  GO_RACE_RESULT="success"

# 4. Orchestrator failure
run_test "Orchestrator failure fails gate" 1 \
  ORCHESTRATE_RESULT="failure" \
  PIPELINE_UNITS_RESULT="skipped" \
  LINT_NAMING_RESULT="success"

# 5. Static check failure
run_test "Lint naming failure fails gate" 1 \
  ORCHESTRATE_RESULT="success" \
  PIPELINE_UNITS_RESULT="success" \
  LINT_NAMING_RESULT="failure"

echo "Ran $CASES tests, $FAILURES failures."
exit "$FAILURES"
