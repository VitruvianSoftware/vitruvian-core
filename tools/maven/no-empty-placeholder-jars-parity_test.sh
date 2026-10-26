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

set -euo pipefail

# --- runfiles bootstrap ---
# shellcheck disable=SC1090,SC1091
source "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" 2>/dev/null ||
	source "$(grep -sm1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null ||
	{
		echo >&2 "ERROR: cannot locate the bash runfiles library"
		exit 1
	}
# --- end runfiles bootstrap ---

SH_BIN="$(rlocation "${SH_TOOL}")"
RS_BIN="$(rlocation "${RS_TOOL}")"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

assert_parity() {
	local case_name="$1"
	local lock_arg="$2"
	local expected_rc="$3"

	local sh_out="${TMP_DIR}/${case_name}.sh.out"
	local sh_err="${TMP_DIR}/${case_name}.sh.err"
	local rs_out="${TMP_DIR}/${case_name}.rs.out"
	local rs_err="${TMP_DIR}/${case_name}.rs.err"

	local sh_rc=0
	LOCK_FILE="${lock_arg}" "${SH_BIN}" >"${sh_out}" 2>"${sh_err}" || sh_rc=$?

	local rs_rc=0
	LOCK_FILE="${lock_arg}" "${RS_BIN}" >"${rs_out}" 2>"${rs_err}" || rs_rc=$?

	if [[ "${sh_rc}" -ne "${expected_rc}" ]]; then
		echo >&2 "FAIL [${case_name}]: sh exit code ${sh_rc} != expected ${expected_rc}"
		exit 1
	fi
	if [[ "${rs_rc}" -ne "${sh_rc}" ]]; then
		echo >&2 "FAIL [${case_name}]: rs exit code ${rs_rc} != sh exit code ${sh_rc}"
		exit 1
	fi
	if ! cmp -s "${sh_out}" "${rs_out}"; then
		echo >&2 "FAIL [${case_name}]: stdout mismatch"
		diff -u "${sh_out}" "${rs_out}" >&2 || true
		exit 1
	fi
	if ! cmp -s "${sh_err}" "${rs_err}"; then
		echo >&2 "FAIL [${case_name}]: stderr mismatch"
		diff -u "${sh_err}" "${rs_err}" >&2 || true
		exit 1
	fi
}

# Case 1: Real repository maven_install.json via runfiles path
assert_parity "real_lockfile" "${REAL_LOCK_FILE}" 0

# Case 2: Clean synthetic lockfile
cat >"${TMP_DIR}/clean.json" <<'EOF'
{
  "artifacts": {
    "com.google.guava:listenablefuture": {
      "shasums": {
        "jar": "d094c2c570d65e13297c1f2e2d02c6c18d71c984"
      },
      "version": "1.0"
    }
  }
}
EOF
assert_parity "clean_synthetic" "${TMP_DIR}/clean.json" 0

# Case 3: Single offending placeholder version
cat >"${TMP_DIR}/offender_single.json" <<'EOF'
{
  "artifacts": {
    "com.google.guava:listenablefuture": {
      "version": "9999.0-empty-to-avoid-conflict-with-guava"
    }
  }
}
EOF
assert_parity "offender_single" "${TMP_DIR}/offender_single.json" 1

# Case 4: Multiple offenders with spaces and tabs
printf '{\n\t  "version": "9999.0-empty-to-avoid-conflict-with-guava",\n    "coord": "com.google.guava:listenablefuture:9999.0-empty-to-avoid-conflict-with-guava"\n}\n' >"${TMP_DIR}/offender_multi.json"
assert_parity "offender_multi" "${TMP_DIR}/offender_multi.json" 1

# Case 5: Missing lockfile
assert_parity "missing_lockfile" "${TMP_DIR}/does_not_exist.json" 1

echo "ok: all maven lockfile guard parity cases passed"
