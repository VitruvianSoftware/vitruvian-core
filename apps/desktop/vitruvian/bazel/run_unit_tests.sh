#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Bazel test wrapper for the unit tests, which Swift Testing runs
# (Tests/SwiftTesting/UnitTests.swift):
#   1. run the binary from the app root, because the tests open repository
#      files (sources, Resources/, build.sh) by app-relative paths;
#   2. on a full run, run Tests/PreferenceCleanupTests.sh;
#   3. always sweep the throwaway UserDefaults suites the tests created;
#   4. fail unless every suite asked for reported its result;
#   5. end the log with TESTS OK or TESTS FAILED, which mutation_checks.py
#      reads.
#
# The suites live in the account's real ~/Library/Preferences: cfprefsd writes
# them there whatever $HOME says, and Bazel points $HOME at TEST_TMPDIR. So the
# sweep resolves the home directory from the account, and the target is tagged
# no-sandbox because the sandbox would refuse those removals.
#
# --suite=<name> runs one suite (repeat it for several; the names are in
# Tests/TestGroups.swift):
#   bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests \
#     --test_arg=--suite=notch
#
# usage: run_unit_tests.sh <test binary> <app dir> [--suite=<name>...]
set -euo pipefail

app_dir="$2"

# Run a copy from a directory of its own. Bundle.main is derived from the
# executable's directory, and in runfiles that directory also holds
# Resources/Info.plist (test data), which CFBundle reads as an old-style bundle:
# the "bare harness" would then report the app's version, so AppInfo.isBeta and
# everything keyed off it would follow the shipped Info.plist instead of the
# "dev" fallback the tests expect. The copy keeps the name the sweep below
# knows, so its own preferences domain goes too.
mkdir -p "$TEST_TMPDIR/bin"
binary="$TEST_TMPDIR/bin/metrics-tests"
cp "$PWD/$1" "$binary"
shift 2

# The suites to run, for UnitTests to read (TestGroups.selected).
selection=""
for argument in "$@"; do
	case "$argument" in
	--suite=?*) selection="${selection:+$selection,}${argument#--suite=}" ;;
	*)
		echo "Unknown test selection: $argument" >&2
		exit 2
		;;
	esac
done
export VITRUVIAN_TEST_SUITES="$selection"

real_home="$(eval echo "~$(id -un)")"

cd "$app_dir"

discard_test_preferences() {
	/bin/zsh -c '
    source <(sed -n "/^discard_test_preferences() {\$/,/^}\$/p" build.sh)
    discard_test_preferences "$1"
  ' zsh "$real_home/Library/Preferences"
}

# A crash prints where it happened, when the toolchain ships the backtracer.
backtracer="$(dirname "$(xcrun --find swift 2>/dev/null || echo /nonexistent)")/../libexec/swift/macosx/swift-backtrace"
if [[ -x "$backtracer" ]]; then
	export SWIFT_BACKTRACE="enable=yes,interactive=no,swift-backtrace=$backtracer"
fi

# Every suite asked for must report its line (`notch: OK (…)`), so a run
# that skips suites cannot pass: Swift Testing would count it green.
if [[ -n "$selection" ]]; then
	expected=$(tr ',' '\n' <<<"$selection" | grep -c .)
else
	expected=$(awk '/static let names = \[/{f=1; next} f && /\]/{exit} f' Tests/TestGroups.swift | grep -c '"')
fi
output="$TEST_TMPDIR/unit-tests.log"

status=0
"$binary" 2>&1 | tee "$output" || status=$?
if [[ $status -ne 0 ]]; then
	# A suite that ends the process prints nothing of its own: say how it
	# ended, and show the system's crash report when it left one.
	if [[ $status -gt 128 ]]; then
		echo "the test binary was killed by signal $((status - 128))"
	else
		echo "the test binary exited with status $status"
	fi
	report="$(ls -t "$real_home/Library/Logs/DiagnosticReports"/metrics-tests* 2>/dev/null | head -1 || true)"
	if [[ -n "$report" ]]; then
		echo "crash report: $report"
		head -c 16000 "$report"
		echo
	fi
fi
reported=$(grep -cE '^[[:alnum:]-]+: (OK|FAILED) \([0-9]+ checks' "$output" || true)
if [[ $reported -ne $expected ]]; then
	echo "$reported of $expected suites reported a result"
	status=1
fi
if [[ $status -eq 0 ]]; then
	echo "TESTS OK ($reported suites)"
else
	echo "TESTS FAILED: the failed checks are listed under their suites above"
fi
if [[ -z "$selection" ]]; then
	/bin/zsh Tests/PreferenceCleanupTests.sh || status=1
fi
discard_test_preferences || status=1
exit "$status"
