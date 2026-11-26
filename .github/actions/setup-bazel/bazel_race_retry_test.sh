#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Tests bazel_race_retry.sh against a fake bazel: it retries the shared repo
# contents cache race (the exact error from merge-queue run 45708649713) and
# nothing else, keeps stdout and exit codes intact, gives up after the retry
# budget, never re-runs a `bazel run` program that started, and installs
# itself without wrapping itself.

set -euo pipefail

SCRIPT="${BAZEL_RACE_RETRY_SCRIPT:?set by the BUILD rule}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd -P)/$(basename "$SCRIPT")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAKE_DIR="$WORK/real"
mkdir -p "$FAKE_DIR"
export FAKE_STATE="$WORK/state"

# The line Bazel 9.3.2 printed in build-test (job 139537040664), colours and all.
RACE_LINE=$'\e[31m\e[1mERROR: \e[0mno such package \'@@gazelle++go_deps+com_github_ipfs_go_ipfs_util//\': error moving repo @@gazelle++go_deps+com_github_ipfs_go_ipfs_util into the repo contents cache: /home/runner/.cache/bazel-repo/contents/9ca0e482b2a184b77723871cbba803d595bbc6e81a94d9b42adc2ec3eeb1a155 (File exists)'
export RACE_LINE

cat >"$FAKE_DIR/bazel" <<'EOF'
#!/usr/bin/env bash
# Fake bazel. FAKE_MODE picks the behaviour; FAKE_STATE counts the calls.
n=$(( $(cat "$FAKE_STATE" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$FAKE_STATE"
case "$FAKE_MODE" in
success)
	printf 'args:'; printf ' [%s]' "$@"; printf '\n'
	exit 0 ;;
race_once)
	if [ "$n" -eq 1 ]; then printf '%s\n' "$RACE_LINE" >&2; exit 1; fi
	echo "stdout from attempt $n"; exit 0 ;;
race_always)
	printf '%s\n' "$RACE_LINE" >&2; exit 1 ;;
other_failure)
	echo "ERROR: //foo:bar failed to build" >&2; exit 3 ;;
run_started)
	echo "INFO: Running command line: bazel-bin/tools/x" >&2
	printf '%s\n' "$RACE_LINE" >&2; exit 1 ;;
esac
EOF
chmod +x "$FAKE_DIR/bazel"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}
calls() { cat "$FAKE_STATE"; }

# Runs the wrapper with the fake as the real bazel; sets OUT, ERR, STATUS.
run_wrapper() {
	rm -f "$FAKE_STATE"
	set +e
	VITRUVIAN_REAL_BAZEL="$FAKE_DIR/bazel" RUNNER_TEMP="$WORK" \
		bash "$SCRIPT" "$@" >"$WORK/out" 2>"$WORK/err"
	STATUS=$?
	set -e
	OUT="$(cat "$WORK/out")"
	ERR="$(cat "$WORK/err")"
}

# 1. Success: one call, stdout and arguments untouched, nothing added to stderr.
FAKE_MODE=success run_wrapper build '//a b:c' --config=x ''
[ "$STATUS" -eq 0 ] || fail "success: exit $STATUS"
[ "$(calls)" -eq 1 ] || fail "success: $(calls) calls"
[ "$OUT" = 'args: [build] [//a b:c] [--config=x] []' ] || fail "success: stdout was '$OUT'"
[ -z "$ERR" ] || fail "success: stderr was '$ERR'"

# 2. The race once: retried, the second attempt's result wins, warning shown,
#    and the first attempt's error still reaches the log.
FAKE_MODE=race_once run_wrapper test //...
[ "$STATUS" -eq 0 ] || fail "race_once: exit $STATUS"
[ "$(calls)" -eq 2 ] || fail "race_once: $(calls) calls, want 2"
[ "$OUT" = "stdout from attempt 2" ] || fail "race_once: stdout was '$OUT'"
grep -Fq "(File exists)" <<<"$ERR" || fail "race_once: the original error was hidden"
grep -Fq "::warning title=Bazel repo contents cache race::@@gazelle++go_deps+com_github_ipfs_go_ipfs_util lost the race" <<<"$ERR" ||
	fail "race_once: no warning naming the repo; stderr was: $ERR"

# 3. The race every time: gives up after the budget with Bazel's exit code.
FAKE_MODE=race_always run_wrapper build //...
[ "$STATUS" -eq 1 ] || fail "race_always: exit $STATUS"
[ "$(calls)" -eq 4 ] || fail "race_always: $(calls) calls, want 1 + 3 retries"
FAKE_MODE=race_always VITRUVIAN_BAZEL_RACE_RETRIES=1 run_wrapper build //...
[ "$(calls)" -eq 2 ] || fail "race_always with 1 retry: $(calls) calls"

# 4. Any other failure: one call, exit code passed through, no warning.
FAKE_MODE=other_failure run_wrapper build //foo:bar
[ "$STATUS" -eq 3 ] || fail "other_failure: exit $STATUS"
[ "$(calls)" -eq 1 ] || fail "other_failure: $(calls) calls"
! grep -Fq "::warning" <<<"$ERR" || fail "other_failure: warned"

# 5. `bazel run` whose program started: never run twice.
FAKE_MODE=run_started run_wrapper run //tools/x
[ "$STATUS" -eq 1 ] || fail "run_started: exit $STATUS"
[ "$(calls)" -eq 1 ] || fail "run_started: $(calls) calls"

# 6. install: wraps the real bazel, records it, puts the shim dir on PATH.
SHIM="$WORK/shim"
export GITHUB_ENV="$WORK/github_env" GITHUB_PATH="$WORK/github_path"
: >"$GITHUB_ENV"
: >"$GITHUB_PATH"
PATH="$FAKE_DIR:$PATH" bash "$SCRIPT" install "$SHIM" >/dev/null
[ -x "$SHIM/bazel" ] || fail "install: no $SHIM/bazel"
grep -Fxq "VITRUVIAN_REAL_BAZEL=$FAKE_DIR/bazel" "$GITHUB_ENV" || fail "install: GITHUB_ENV was: $(cat "$GITHUB_ENV")"
grep -Fxq "$SHIM" "$GITHUB_PATH" || fail "install: GITHUB_PATH was: $(cat "$GITHUB_PATH")"

# 7. A second install in the same job (setup-bazel used twice), with the shim
#    already first on PATH, must still wrap the real bazel, not itself.
: >"$GITHUB_ENV"
PATH="$SHIM:$FAKE_DIR:$PATH" bash "$SCRIPT" install "$SHIM" >/dev/null
grep -Fxq "VITRUVIAN_REAL_BAZEL=$FAKE_DIR/bazel" "$GITHUB_ENV" || fail "reinstall wrapped: $(cat "$GITHUB_ENV")"
: >"$GITHUB_ENV"
VITRUVIAN_REAL_BAZEL="$SHIM/bazel" PATH="$SHIM:$FAKE_DIR:$PATH" bash "$SCRIPT" install "$SHIM" >/dev/null
grep -Fxq "VITRUVIAN_REAL_BAZEL=$FAKE_DIR/bazel" "$GITHUB_ENV" || fail "reinstall over a recorded shim wrapped itself: $(cat "$GITHUB_ENV")"

# 8. The installed wrapper works through PATH alone (no VITRUVIAN_REAL_BAZEL),
#    and `bazel install` is passed to Bazel rather than reinstalling.
rm -f "$FAKE_STATE"
out="$(env -u VITRUVIAN_REAL_BAZEL PATH="$SHIM:$FAKE_DIR:$PATH" FAKE_MODE=success RUNNER_TEMP="$WORK" bazel install x)"
[ "$out" = 'args: [install] [x]' ] || fail "PATH lookup: stdout was '$out'"
rm -f "$FAKE_STATE"
set +e
env -u VITRUVIAN_REAL_BAZEL PATH="$SHIM:$FAKE_DIR:$PATH" FAKE_MODE=race_once RUNNER_TEMP="$WORK" bazel build //... >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 0 ] && [ "$(calls)" -eq 2 ] || fail "installed wrapper: exit $status after $(calls) calls"

echo "PASS: bazel_race_retry"
