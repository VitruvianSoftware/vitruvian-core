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
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# The canary: runs a test binary that is meant to FAIL, and passes only when it
# fails in the way it should.
#
#   expect_failure.sh <test binary> <test name prefix> [required test...]
#
# or, where the caller cannot pass arguments (rules_itest's service_test starts
# its test with none), the same as EXPECT_FAILURE_BINARY (a runfiles path),
# EXPECT_FAILURE_PREFIX and EXPECT_FAILURE_REQUIRED (test names, separated by
# spaces).
#
# The binary here is the relay's tenant isolation tests built against a relay
# with one ownership check deliberately broken. Passing means all of:
#
#   1. the binary exited non-zero;
#   2. every required test is reported FAILED. These are the tests that exist
#      to notice this break, so one of them passing means the break went
#      unseen (and a test that fails for another reason does not count for it);
#   3. at least one test with the prefix passed, so the database and the relay
#      worked and the failures are the tests noticing the break, not the
#      harness falling over (that would fail every test).
#
# If the binary passes, the isolation tests cannot see the break they exist to
# catch, and this exits 1.

set -u

required=""
if [ "$#" -ge 2 ]; then
	binary="$1"
	prefix="$2"
	shift 2
	required="$*"
elif [ "$#" -eq 0 ] && [ -n "${EXPECT_FAILURE_BINARY:-}" ] && [ -n "${EXPECT_FAILURE_PREFIX:-}" ]; then
	binary="$EXPECT_FAILURE_BINARY"
	prefix="$EXPECT_FAILURE_PREFIX"
	required="${EXPECT_FAILURE_REQUIRED:-}"
else
	echo "usage: expect_failure.sh <test binary> <test name prefix> [required test...]" >&2
	exit 2
fi

# A runfiles path, as `$(rootpath ...)` gives it, may be relative to the
# runfiles tree rather than to where this was started.
if [ ! -x "$binary" ]; then
	for tree in "${RUNFILES_DIR:-}" "${TEST_SRCDIR:-}"; do
		for workspace in "${TEST_WORKSPACE:-_main}" _main; do
			if [ -n "$tree" ] && [ -x "$tree/$workspace/$binary" ]; then
				binary="$tree/$workspace/$binary"
				break 2
			fi
		done
	done
fi
if [ ! -x "$binary" ]; then
	echo "expect_failure: no test binary at $binary (cwd $PWD)" >&2
	exit 2
fi

out="$(mktemp "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/expect_failure.XXXXXX")" || exit 2
trap 'rm -f "$out"' EXIT

# The inner test is not the test Bazel is running: its own report file must not
# overwrite this one's.
env -u XML_OUTPUT_FILE "$binary" >"$out" 2>&1
status=$?

cat "$out"
echo
echo "expect_failure: the inner test exited $status"

if [ "$status" -eq 0 ]; then
	echo "CANARY FAILED: the build with its ownership check broken passed every ${prefix} test." >&2
	echo "The isolation tests would not catch a real break." >&2
	exit 1
fi

# Libtest prints `test <name> ... FAILED` or `... ok`, one line per test.
failed="$(grep -E "^test ${prefix}[A-Za-z0-9_:]+ \.\.\. FAILED" "$out")"
passed="$(grep -E "^test ${prefix}[A-Za-z0-9_:]+ \.\.\. ok" "$out")"

if [ -z "$failed" ]; then
	echo "CANARY FAILED: the inner test exited $status, but no ${prefix} test is reported FAILED." >&2
	echo "It failed for some other reason (the build, or starting up)." >&2
	exit 1
fi

missed=""
for name in $required; do
	if ! grep -qxF "test $name ... FAILED" "$out"; then
		missed="$missed $name"
	fi
done
if [ -n "$missed" ]; then
	echo "CANARY FAILED: these tests should have noticed the break, but did not fail:" >&2
	for name in $missed; do
		echo "  $name" >&2
	done
	echo "The break is going unseen by the tests that exist to catch it." >&2
	exit 1
fi

if [ -z "$passed" ]; then
	echo "CANARY FAILED: every ${prefix} test failed, none passed." >&2
	echo "That is the harness (the database, the relay) not working, not the break being noticed." >&2
	exit 1
fi

echo "CANARY OK: the broken build fails these ${prefix} tests, as it must:"
echo "$failed"
exit 0
