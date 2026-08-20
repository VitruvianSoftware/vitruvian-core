#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Regression harness for publish-dev-latest.sh. Runs the REAL script against a
# fake workspace with recording stubs for bazel/gh/node, then asserts the
# script's observable contract:
#
#   1. every `gh release` call runs from the WORKSPACE ROOT — gh resolves the
#      target repository from the git remote of its cwd, and $WORK is not a
#      repo. The first orchestrated CI run of this unit failed exactly here:
#      the legacy stamp/publish steps were separate (each step restarts at the
#      workspace root), and merging them into one script leaked the stamp
#      step's `cd "$WORK"` into the gh calls.
#   2. the published bundle's build_info.json is actually re-stamped with the
#      real commit (not the hermetic placeholder).
#   3. both assets are uploaded with --clobber to the rolling tag.
set -euo pipefail

SCRIPT="$TEST_SRCDIR/_main/tabula/extension/publish-dev-latest.sh"
FAKE_ROOT="$TEST_TMPDIR/workspace"
STUBS="$TEST_TMPDIR/stubs"
WORK="$TEST_TMPDIR/runner-temp"
GH_LOG="$TEST_TMPDIR/gh.log"
mkdir -p "$FAKE_ROOT/tabula/extension" "$FAKE_ROOT/bazel-bin/tabula/extension" "$STUBS" "$WORK"

# --- fake workspace ---------------------------------------------------------
printf '{"version":"9.9.9-test"}\n' >"$FAKE_ROOT/tabula/extension/package.json"
# A real zip whose build_info.json is the hermetic placeholder, as webpack ships it.
(cd "$TEST_TMPDIR" &&
	printf '{"commit":"PLACEHOLDER"}\n' >build_info.json &&
	zip -q "$FAKE_ROOT/bazel-bin/tabula/extension/tabula-extension-chrome.zip" build_info.json &&
	rm build_info.json)

# --- recording stubs --------------------------------------------------------
cat >"$STUBS/bazel" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$STUBS/gh" <<EOF
#!/usr/bin/env bash
echo "\$PWD|\$*" >> "$GH_LOG"
exit 0
EOF
cat >"$STUBS/node" <<'EOF'
#!/usr/bin/env bash
echo "9.9.9-test"
EOF
chmod +x "$STUBS"/bazel "$STUBS"/gh "$STUBS"/node

# --- run the real script ----------------------------------------------------
env -i PATH="$STUBS:/usr/bin:/bin" \
	BUILD_WORKSPACE_DIRECTORY="$FAKE_ROOT" \
	RUNNER_TEMP="$WORK" \
	GITHUB_SHA="deadbeefcafe" \
	GH_TOKEN="test-token" \
	bash "$SCRIPT"

# --- assertions -------------------------------------------------------------
fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[ -s "$GH_LOG" ] || fail "no gh invocations recorded"
while IFS='|' read -r cwd args; do
	[ "$cwd" = "$FAKE_ROOT" ] ||
		fail "gh ran from '$cwd' (not the workspace root); gh cannot resolve the repo outside it. args: $args"
done <"$GH_LOG"

grep -q 'release upload tabula-extension-dev-latest' "$GH_LOG" || fail "no release upload recorded"
grep -q -- '--clobber' "$GH_LOG" || fail "upload missing --clobber"

# The stamped identity must have replaced the placeholder inside the zip.
unzip -p "$WORK/tabula-extension-chrome.zip" build_info.json >"$TEST_TMPDIR/stamped.json"
grep -q 'deadbeefcafe' "$TEST_TMPDIR/stamped.json" || fail "bundle not re-stamped: $(cat "$TEST_TMPDIR/stamped.json")"
grep -q 'PLACEHOLDER' "$TEST_TMPDIR/stamped.json" && fail "placeholder survived in build_info.json"

# The standalone identity asset is published from $WORK by absolute path.
[ -f "$WORK/build_info.json" ] || fail "standalone build_info.json missing from \$WORK"

echo "PASS"
