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

# The SessionStart hook for cloud sessions: runs the three setup steps one after
# another, in the order each depends on the last.
#
#   1. tools/cloud-bootstrap/cloud-bootstrap.sh installs the CLIs the profile
#      lists (tailscale among them) and writes session.env, which carries any
#      TS_AUTHKEY, LAB_SA_TOKEN or CLAUDE_SSH_KEY it fetched from Secret Manager.
#   2. .claude/tailscale-up.sh needs that binary and that TS_AUTHKEY.
#   3. .claude/kube-setup.sh needs LAB_SA_TOKEN and CLAUDE_SSH_KEY from
#      session.env, and the tailnet tailscale-up.sh joins.
#
# They used to be three hooks in .claude/settings.json, but Claude Code runs every
# hook of an event in parallel, so steps 2 and 3 read session.env before step 1
# had written it: on 2026-10-09 kube-setup.sh wrote its kubeconfig half a second
# before cloud-bootstrap.sh wrote session.env. A credential kept in Secret
# Manager, as the docs recommend, could miss the session that fetched it, and on
# a fresh machine tailscale-up.sh could look for tailscale before it was
# installed.
#
# Each step is best-effort and exits 0 on its own failures; a step that fails
# anyway does not stop the next, and this script always exits 0, so the session
# always starts. Their stdout, which the agent sees, comes through in order.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${root}/tools/cloud-bootstrap/cloud-bootstrap.sh"
"${root}/.claude/tailscale-up.sh"
"${root}/.claude/kube-setup.sh"
exit 0
