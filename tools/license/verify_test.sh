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

# verify_test.sh — self-test for tools/license/verify.sh.
#
# verify.sh backs `license-check`, a REQUIRED merge-queue check, and until now
# had NO test of any kind: it is a `bazel run` sh_binary with no sh_test, so
# neither `bazel test //...` nor the nightly periodic-full-sweep exercised it.
# A false FAIL there blocks every PR in the queue, so the behaviour that most
# needs a guard is that a VALID header is never flagged.
#
# The headline case is `big-header-wrong-holder`, which pins the SIGPIPE bug the
# herestrings in verify.sh fixed. With the old `printf '%s' "$hdr" | grep -q ...`
# form, `grep -q` exits the instant it matches; if the header is larger than the
# 64 KiB pipe buffer the still-writing `printf` takes SIGPIPE, and
# `set -o pipefail` surfaces 141 as the pipeline's status. Which line races
# decides which way the check breaks:
#
#   - line 68 (`... || continue`) racing SKIPS the file — a bad header walks
#     straight through the required check. That is what this case pins: the old
#     script exits 0 on a wrong-holder file, the fixed one flags it.
#   - line 74 racing INVERTS `if !` and flags a valid file. That is the observed
#     production failure: run 31064957694 (2026-08-06) failed the REQUIRED
#     license-check on gcp-projects/business_unit_2/production/outputs.go with
#     "holder is not 'VitruvianSoftware'" at a commit where that file's first
#     line reads `// Copyright (c) 2026 VitruvianSoftware`.
#
# A herestring has no second process, so neither direction can happen.
#
# Run: bash tools/license/verify_test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNDER_TEST="${SCRIPT_DIR}/verify.sh"

PASS=0
FAIL=0

MIT_BODY='//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction.'

# Builds a throwaway git repo carrying the six first-party LICENSE files
# verify.sh requires, plus whatever fixture the caller drops in via $1 (a
# function run with the repo root as cwd), then runs verify.sh against it.
#
# run_case <name> <expected pass|fail> <fixture-fn> [expected-substring]
run_case() {
  local name="$1" expected="$2" fixture="$3" want="${4:-}"
  local tmp out status
  tmp="$(mktemp -d)"
  (
    cd "${tmp}"
    git init -q .
    git config user.email t@example.com
    git config user.name t
    for app in tabula oauth-user-inspector devx homelab mcp-slack nexus-agent; do
      mkdir -p "${app}"
      printf 'MIT License\n\nCopyright (c) 2026 VitruvianSoftware\n' >"${app}/LICENSE"
    done
    "${fixture}"
    git add -A
  )
  # verify.sh cd's to BUILD_WORKSPACE_DIRECTORY and enumerates via `git ls-files`,
  # so pointing it at the fixture repo exercises the real script end to end.
  set +e
  out="$(BUILD_WORKSPACE_DIRECTORY="${tmp}" bash "${UNDER_TEST}" 2>&1)"
  status=$?
  set -e
  rm -rf "${tmp}"

  local ok=1
  if [ "${expected}" = "pass" ] && [ "${status}" -ne 0 ]; then ok=0; fi
  if [ "${expected}" = "fail" ] && [ "${status}" -eq 0 ]; then ok=0; fi
  if [ -n "${want}" ] && ! grep -qF "${want}" <<<"${out}"; then ok=0; fi

  if [ "${ok}" = "1" ]; then
    echo "PASS  ${name}"
    PASS=$((PASS + 1))
  else
    echo "FAIL  ${name}: expected ${expected}${want:+ containing [${want}]}, got status ${status}"
    printf '%s\n' "${out}" | sed 's/^/        | /'
    FAIL=$((FAIL + 1))
  fi
}

fixture_valid() {
  printf '// Copyright (c) 2026 VitruvianSoftware\n%s\n\npackage main\n' "${MIT_BODY}" >a.go
}

# Writes a header whose `head -30` window is ~200 KiB — far past the 64 KiB pipe
# buffer — while keeping every pattern verify.sh matches on lines 1-3.
big_header() {
  local holder="$1" out="$2" pad
  pad="$(head -c 8192 /dev/zero | tr '\0' 'x')"
  {
    printf '// Copyright (c) 2026 %s\n' "${holder}"
    printf '%s\n' "${MIT_BODY}"
    for _ in $(seq 1 25); do printf '// %s\n' "${pad}"; done
    printf '\npackage main\n'
  } >"${out}"
}

fixture_big_valid() { big_header VitruvianSoftware big.go; }

# THE REGRESSION GUARD. Pre-fix, the oversized header made line 68's
# `printf | grep -qi ... || continue` return 141, so the file was skipped and
# this bad header sailed through the required check (script exits 0). Post-fix
# it is flagged. Verified both ways before this test was committed.
fixture_big_wrong_holder() { big_header 'Somebody Else' bigbad.go; }

fixture_wrong_holder() {
  printf '// Copyright (c) 2026 Somebody Else\n%s\n\npackage main\n' "${MIT_BODY}" >bad.go
}

fixture_apache() {
  printf '// Copyright 2026 VitruvianSoftware\n//\n// Licensed under the Apache License, Version 2.0\n\npackage main\n' >apache.go
}

fixture_no_header() {
  printf 'package main\n\nfunc main() {}\n' >plain.go
}

fixture_missing_license_file() {
  fixture_valid
  rm -f tabula/LICENSE
}

run_case "valid-header"            pass "fixture_valid"
run_case "big-valid-header"        pass "fixture_big_valid"
run_case "no-header-skipped"       pass "fixture_no_header"
run_case "wrong-holder"            fail "fixture_wrong_holder" "license header holder is not 'VitruvianSoftware'"
run_case "big-header-wrong-holder" fail "fixture_big_wrong_holder" "license header holder is not 'VitruvianSoftware'"
run_case "non-mit-header"          fail "fixture_apache" "has a non-MIT license header"
run_case "missing-LICENSE"         fail "fixture_missing_license_file" "tabula/LICENSE is missing"

echo
echo "verify_test: ${PASS} passed, ${FAIL} failed."
[ "${FAIL}" -eq 0 ]
