#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Bazel test wrapper for the upstream unit-test binary, mirroring
# `build.sh --test`:
#   1. run the binary from the app root, because the tests open repository
#      files (sources, Resources/, build.sh) by app-relative paths;
#   2. on a full run, run Tests/PreferenceCleanupTests.sh;
#   3. always sweep the throwaway UserDefaults suites the tests created.
#
# The suites live in the account's real ~/Library/Preferences: cfprefsd writes
# them there whatever $HOME says, and Bazel points $HOME at TEST_TMPDIR. So the
# sweep resolves the home directory from the account, and the target is tagged
# no-sandbox because the sandbox would refuse those removals.
#
# Extra arguments pass through to the binary (e.g. --suite=notch, --list):
#   bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests \
#     --test_arg=--suite=notch
#
# usage: run_unit_tests.sh <test binary> <app dir> [binary args...]
set -euo pipefail

app_dir="$2"

# Run a copy from a directory of its own. Bundle.main is derived from the
# executable's directory, and in runfiles that directory also holds
# Resources/Info.plist (test data), which CFBundle reads as an old-style bundle:
# the "bare harness" would then report the app's version, so AppInfo.isBeta and
# everything keyed off it would follow the shipped Info.plist instead of the
# "dev" fallback the tests expect. The copy is named like build.sh's binary, so
# its own preferences domain is the one the sweep below removes.
mkdir -p "$TEST_TMPDIR/bin"
binary="$TEST_TMPDIR/bin/metrics-tests"
cp "$PWD/$1" "$binary"
shift 2

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

status=0
"$binary" "$@" || status=$?
if [[ $# -eq 0 ]]; then
	/bin/zsh Tests/PreferenceCleanupTests.sh || status=1
fi
discard_test_preferences || status=1
exit "$status"
