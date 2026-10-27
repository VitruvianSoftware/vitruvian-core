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

# Produces space-separated key-values for stamp variables.
# Those starting with "STABLE_" will cause actions to re-run when they change.
# See https://registry.bazel.build/docs/bazel_lib/3.0.0#lib-stamping-bzl
set -o errexit -o nounset -o pipefail

inside_work_tree=$(git rev-parse --is-inside-work-tree 2>/dev/null || true)

# Encourage developers to setup githooks
IFS='' read -r -d '' GITHOOKS_MSG <<"EOF" || true
    cat <<EOF
  It looks like the git config option core.hooksPath is not set.
  This repository uses hooks stored in tools/githooks/ to run tools such as formatters.
  You can disable this warning by running:

    echo "common --workspace_status_command=" >> ~/.bazelrc

  To set up the hooks, please run:

    git config core.hooksPath tools/githooks
EOF

if [ "${inside_work_tree}" = "true" ] && [ "$EUID" -ne 0 ] && [ -z "$(git config core.hooksPath || true)" ]; then
	echo >&2 "${GITHOOKS_MSG}"
fi

# Primary-checkout branch guard (#502).
if [ "${inside_work_tree}" = "true" ] \
	&& [ -z "${CI:-}" ] && [ -z "${GITHUB_ACTIONS:-}" ] \
	&& [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] \
	&& [ "${VITRUVIAN_ALLOW_PRIMARY_BRANCH:-0}" != "1" ]; then
	git_dir=$(git rev-parse --git-dir 2>/dev/null || true)
	git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null || true)
	if [ -n "${git_dir}" ] && [ "${git_dir}" = "${git_common_dir}" ]; then
		branch=$(git symbolic-ref --short -q HEAD || echo "(detached)")
		if [ "${branch}" != "main" ]; then
			cat >&2 <<GUARD
  ✗ Bazel invocation refused: the PRIMARY checkout is on '${branch}', not 'main'.

  This checkout is shared across concurrent sessions — branch work here stomps
  other sessions' HEAD and contends on one Bazel server (#455/#502).

  Do branch work in an isolated worktree instead:

      git switch main
      bazel run //tools/worktree -- ${branch}

  Break-glass override (only if you are certain nothing else shares this
  checkout right now):

      export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1
GUARD
			exit 1
		fi
	fi
fi

# Pinned Xcode (macOS only, warn-only).
if [ "$(uname -s)" = "Darwin" ] && [ -z "${CI:-}" ] && [ -f .xcode-version ]; then
	want_xcode=$(tr -d '[:space:]' <.xcode-version)
	dev_dir=$(xcode-select -p 2>/dev/null || true)
	have_xcode=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
		"${dev_dir%/Contents/Developer}/Contents/Info.plist" 2>/dev/null || echo "none (Command Line Tools only)")
	case "${have_xcode}" in
	"${want_xcode}" | "${want_xcode}".*) ;;
	*)
		echo "  ⚠ Xcode ${have_xcode} is selected, but CI builds Swift with Xcode ${want_xcode} (.xcode-version)." >&2
		echo "    Swift results may differ from CI. Fix: sudo xcode-select -s /Applications/Xcode.app  (after installing Xcode ${want_xcode})" >&2
		;;
	esac
fi

if [ "${1:-}" = "--check-only" ]; then
	exit 0
fi

git_commit=$(git rev-parse HEAD)

# Follows https://blog.aspect.build/versioning-releases-from-a-monorepo
auto_version=$(
	git describe --tags --long --match="[0-9][0-9][0-9][0-9].[0-9][0-9]" |
		sed -e 's/-/./;s/-g/-/'
)

cat <<EOF
STABLE_GIT_COMMIT ${git_commit}
STABLE_MONOREPO_VERSION ${auto_version}
EOF
