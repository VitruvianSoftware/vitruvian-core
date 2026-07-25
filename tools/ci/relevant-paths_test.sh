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

# relevant-paths_test.sh — self-test for tools/ci/relevant-paths.sh.
#
# The property that matters most here is NOT the docs-only fast path (that only
# costs lead time if it regresses) but the IGNORE_REGEX narrowing that
# license-check depends on: license-check MUST still run on a gitops-only diff,
# because addlicense does not ignore gitops/ and //tools/license:{check,verify}
# are `bazel run` sh_binaries with no sh_test -- so neither `bazel test //...`
# nor the nightly periodic-full-sweep would ever catch an unlicensed gitops file
# that slipped past the required check.
#
# Run: bash tools/ci/relevant-paths_test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNDER_TEST="${SCRIPT_DIR}/relevant-paths.sh"

# The lane gate under test is read STRAIGHT OUT of ci.yaml rather than copied
# here: a literal would let the workflow drift to an unsafe ignore set while
# this test kept asserting the old safe one. Extracting it means the assertions
# below always describe what CI actually does.
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
CI_YAML="${REPO_ROOT}/.github/workflows/ci.yaml"
FOUND="$(grep -cE "^\s+IGNORE_REGEX:" "${CI_YAML}" || true)"
if [ "${FOUND}" != "1" ]; then
  echo "relevant-paths_test: expected exactly 1 IGNORE_REGEX in ci.yaml, found ${FOUND}." >&2
  echo "  If another lane now narrows its ignore set too, extend this test to cover it." >&2
  exit 1
fi
LICENSE_IGNORE_REGEX="$(grep -E "^\s+IGNORE_REGEX:" "${CI_YAML}" | sed -E "s/^[^']*'(.*)'[[:space:]]*$/\1/")"
echo "relevant-paths_test: license-check IGNORE_REGEX from ci.yaml = '${LICENSE_IGNORE_REGEX}'"
echo

PASS=0
FAIL=0

# run_case <name> <expected true|false> <ignore-regex|""> <file>...
# Builds a throwaway git repo, commits a base, changes the named files, then
# runs relevant-paths.sh against that diff and compares the emitted verdict.
run_case() {
  name="$1"; expected="$2"; ignore="$3"; shift 3

  tmp="$(mktemp -d)"
  (
    cd "${tmp}"
    git init -q .
    git config user.email t@example.com
    git config user.name t
    mkdir -p docs gitops/argocd tabula/api
    echo base > docs/.keep
    git add -A
    git commit -qm base
    base_rev="$(git rev-parse HEAD)"

    for f in "$@"; do
      mkdir -p "$(dirname "$f")"
      echo change >> "$f"
    done
    git add -A
    git commit -qm change

    if [ -n "${ignore}" ]; then
      BEFORE_REV="${base_rev}" IGNORE_REGEX="${ignore}" bash "${UNDER_TEST}"
    else
      BEFORE_REV="${base_rev}" bash "${UNDER_TEST}"
    fi
  ) > "${tmp}/out.txt" 2>&1 || true

  if grep -q "relevant=${expected}" "${tmp}/out.txt"; then
    printf '  \033[32mPASS\033[0m  %s\n' "${name}"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m  %s\n' "${name}"
    printf '        expected relevant=%s, got:\n' "${expected}"
    sed 's/^/          /' "${tmp}/out.txt"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "${tmp}"
}

echo "relevant-paths_test: default ignore set (Bazel build lanes)"
run_case "docs-only skips"                      false "" docs/guide.md
run_case "markdown-only skips"                  false "" README.md
run_case "gitops-only skips"                    false "" gitops/argocd/app.yaml
run_case "source change runs"                   true  "" tabula/api/src/index.ts
run_case "mixed docs+source runs"               true  "" docs/guide.md tabula/api/src/index.ts

echo
echo "relevant-paths_test: license-check ignore set (gitops must NOT be skippable)"
run_case "docs-only skips"                      false "${LICENSE_IGNORE_REGEX}" docs/guide.md
run_case "markdown-only skips"                  false "${LICENSE_IGNORE_REGEX}" README.md
# THE guard: a gitops manifest needs an MIT header and no other lane checks it.
run_case "gitops-only RUNS (no license backstop)" true "${LICENSE_IGNORE_REGEX}" gitops/argocd/app.yaml
run_case "nested docs/ runs (conservative)"     true  "${LICENSE_IGNORE_REGEX}" tabula/docs/notes.txt
run_case "source change runs"                   true  "${LICENSE_IGNORE_REGEX}" tabula/api/src/index.ts

echo
echo "relevant-paths_test: fail-safe"
# No BEFORE_REV and no BASE_REF at all -> must run the heavy work.
if BEFORE_REV="" BASE_REF="" bash "${UNDER_TEST}" 2>&1 | grep -q 'relevant=true'; then
  printf '  \033[32mPASS\033[0m  no diff base -> runs\n'; PASS=$((PASS + 1))
else
  printf '  \033[31mFAIL\033[0m  no diff base -> should run\n'; FAIL=$((FAIL + 1))
fi

echo
if [ "${FAIL}" -ne 0 ]; then
  printf '\033[31mFAIL\033[0m — %d passed, %d failed\n' "${PASS}" "${FAIL}"
  exit 1
fi
printf '\033[32mPASS\033[0m — %d passed\n' "${PASS}"
