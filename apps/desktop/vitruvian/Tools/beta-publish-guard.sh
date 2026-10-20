#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Decides whether a beta publish may go ahead, from how the commit being
# published relates to the commit the rolling tag already points at. Prints one
# word, and never touches the network:
#   Tools/beta-publish-guard.sh <status>
#
# <status> is `status` from GitHub's compare API for <tag commit>...<this
# commit> (gh api repos/{owner}/{repo}/compare/<tag>...<sha> --jq .status), or
# `absent` when the tag does not exist yet.
#
#   absent, ahead, identical   publish   nothing newer is on the release; a
#                                        re-run of the same commit is fine
#   behind                     skip      the release already holds a newer
#                                        build; uploading would put an older
#                                        DMG over it
#   anything else              refuse    diverged cannot happen on main, and an
#                                        answer we do not know is not a yes
#
# Two beta jobs for two pushes can run out of order (one concurrency group
# queues them, and does not order them by commit). The older one used to upload
# its DMGs over the newer one's and then fail moving the tag backwards.
set -eu

case "${1:-}" in
absent | ahead | identical) echo publish ;;
behind) echo skip ;;
*) echo refuse ;;
esac
