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
#
# Fails when maven_install.json pins an artifact to a version that is a
# deliberately EMPTY placeholder jar.
#
# Why this exists. Some Maven coordinates publish a version whose jar contains
# no classes at all, purely so the dependency graph can dedupe it against the
# artifact that really owns those classes. The canonical one is
# com.google.guava:listenablefuture:9999.0-empty-to-avoid-conflict-with-guava:
# the 9999.0 version number is chosen to win every version comparison, and the
# jar is empty because real guava supplies ListenableFuture.
#
# That is a landmine for an Android binary that does NOT depend on guava.
# androidx.activity, androidx.compose.ui and androidx.lifecycle each pull
# androidx.profileinstaller, which pulls androidx.concurrent:concurrent-futures,
# whose AbstractResolvableFuture IMPLEMENTS ListenableFuture. Resolve
# listenablefuture to the empty jar and the class is simply absent from the
# APK: AbstractResolvableFuture ships without its supertype, and
# ProfileInstaller's androidx.startup initializer -- which runs on every launch
# whether or not the app ships a baseline profile -- dies with
# NoClassDefFoundError on a background thread, taking the process down before
# the first frame.
#
# Nothing catches this earlier. It compiles cleanly (the class is only needed
# at runtime class-resolution time), so a build-and-unit-test lane stays green
# while the app cannot start at all. That is exactly what happened: the app
# shipped to main crashing on launch on every device, with all CI green.
#
# The fix is always to state the real version explicitly in MODULE.bazel, which
# wins because version_conflict_policy = "pinned". For listenablefuture that is
# 1.0, a ~5 KB jar holding exactly the one interface.
set -euo pipefail

# --- runfiles bootstrap (https://github.com/bazelbuild/bazel/tree/master/tools/bash) ---
# shellcheck disable=SC1090,SC1091
source "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" 2>/dev/null ||
	source "$(grep -sm1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null ||
	{
		echo >&2 "ERROR: cannot locate the bash runfiles library"
		exit 1
	}
# --- end runfiles bootstrap ---

lock_path="$(rlocation "${LOCK_FILE}")"
if [[ ! -f "${lock_path}" ]]; then
	echo >&2 "ERROR: cannot read the lock file at '${lock_path}'"
	exit 1
fi

# Substrings that only ever appear in a placeholder version string. Kept as a
# list so a second one can be added without reworking the check; matching is
# on the VERSION, never the coordinate, so a legitimately-named artifact is
# never caught by accident.
placeholders=(
	"empty-to-avoid-conflict"
)

rc=0
for marker in "${placeholders[@]}"; do
	# -F: the marker is a literal, not a pattern. A herestring rather than a
	# pipe, so grep cannot exit 141 on SIGPIPE under pipefail and report a
	# false clean verdict.
	while IFS= read -r offender; do
		[[ -z "${offender}" ]] && continue
		echo >&2 "FAIL: ${offender}"
		echo >&2 "      pins a placeholder version whose jar contains no classes."
		echo >&2 "      Anything whose supertype lives in that jar will compile and"
		echo >&2 "      then fail to resolve at runtime. State the real version in"
		echo >&2 "      MODULE.bazel (version_conflict_policy = \"pinned\" makes a"
		echo >&2 "      directly-declared version win) and re-pin with:"
		echo >&2 "        bazel run @unpinned_maven//:pin"
		rc=1
	done < <(grep -F "${marker}" <<<"$(cat "${lock_path}")" | sed 's/^[[:space:]]*//' || true)
done

if [[ ${rc} -eq 0 ]]; then
	echo "ok: no placeholder-version artifacts in the Maven lock file"
fi
exit "${rc}"
