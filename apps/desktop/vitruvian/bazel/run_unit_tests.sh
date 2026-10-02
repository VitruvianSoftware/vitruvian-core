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

binary="$PWD/$1"
app_dir="$2"
shift 2

real_home="$(eval echo "~$(id -un)")"

cd "$app_dir"

discard_test_preferences() {
	/bin/zsh -c '
    source <(sed -n "/^discard_test_preferences() {\$/,/^}\$/p" build.sh)
    discard_test_preferences "$1"
  ' zsh "$real_home/Library/Preferences"
}

status=0
"$binary" "$@" || status=$?
if [[ $# -eq 0 ]]; then
	/bin/zsh Tests/PreferenceCleanupTests.sh || status=1
fi
discard_test_preferences || status=1
exit "$status"
