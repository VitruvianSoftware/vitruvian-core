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

inside_work_tree=$(git rev-parse --is-inside-work-tree 2>/dev/null)

# Encourage developers to setup githooks
IFS='' read -r -d '' GITHOOKS_MSG <<"EOF"
    cat <<EOF
  It looks like the git config option core.hooksPath is not set.
  This repository uses hooks stored in githooks/ to run tools such as formatters.
  You can disable this warning by running:

    echo "common --workspace_status_command=" >> ~/.bazelrc

  To set up the hooks, please run:

    git config core.hooksPath githooks
EOF

if [ "${inside_work_tree}" = "true" ] && [ "$EUID" -ne 0 ] && [ -z "$(git config core.hooksPath)" ]; then
	echo >&2 "${GITHOOKS_MSG}"
fi

# ---------------------------------------------------------------------------
# Primary-checkout branch guard (#502). This checkout is routinely shared by
# multiple concurrent sessions/agents: branch work in the PRIMARY checkout
# stomps everyone's HEAD and serializes them onto one Bazel server. The
# supported flow is `bazel run //tools/worktree -- <branch>` (issue #455),
# which gives each branch its own worktree AND its own Bazel output root.
#
# This script is the repo's workspace_status_command, so it runs before every
# `bazel build/run/test` — making the worktree flow structural instead of
# convention (#502): a Bazel invocation from the PRIMARY checkout on a
# non-main HEAD FAILS with the message below (a failing workspace status
# aborts the build).
#
# Deliberately exempt:
#   * linked worktrees            (git-dir != git-common-dir) — the sanctioned
#                                 flow; branches there are the whole point.
#   * CI                          ($CI / $GITHUB_ACTIONS) — runners check out
#                                 branches/merge refs in a fresh clone; there
#                                 is no shared-HEAD hazard.
#   * VITRUVIAN_ALLOW_PRIMARY_BRANCH=1  explicit break-glass for a human who
#                                 knows the checkout is not shared right now.
#
# Detached HEAD in the primary checkout is treated as non-main (same hazard).
if [ "${inside_work_tree}" = "true" ] \
	&& [ -z "${CI:-}" ] && [ -z "${GITHUB_ACTIONS:-}" ] \
	&& [ "${VITRUVIAN_ALLOW_PRIMARY_BRANCH:-0}" != "1" ]; then
	git_dir=$(git rev-parse --git-dir 2>/dev/null)
	git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
	if [ -n "${git_dir}" ] && [ "${git_dir}" = "${git_common_dir}" ]; then
		# Primary checkout (not a linked worktree).
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
