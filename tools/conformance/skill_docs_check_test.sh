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

# Self-test for skill_docs_check.sh: verifies passing on valid links/paths and
# failure on broken relative links and missing backticked paths.

set -euo pipefail

CHECK="$(cd "$(dirname "$0")" && pwd)/skill_docs_check.sh"
[[ -f "$CHECK" ]] || CHECK="${TEST_SRCDIR:-}/_main/tools/conformance/skill_docs_check.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/pkg/.agent/skills/demo" "$T/pkg/src" "$T/pkg/docs"
touch "$T/pkg/src/main.rs" "$T/pkg/docs/guide.md"

cat >"$T/pkg/.agent/skills/demo/SKILL.md" <<'MD'
# Demo Skill

- [Guide](../../../docs/guide.md#section)
- [External](https://example.com)
- Source: `src/main.rs`
MD

if (cd "$T" && bash "$CHECK" --root pkg pkg/.agent/skills/demo/SKILL.md); then
  echo "PASS: valid links and paths accepted"
else
  echo "FAIL: valid links and paths rejected" >&2
  exit 1
fi

cat >"$T/pkg/.agent/skills/demo/BAD_LINK.md" <<'MD'
# Bad Link
- [Missing](../../../../mkdocs.yml)
MD

if (cd "$T" && bash "$CHECK" --root pkg pkg/.agent/skills/demo/BAD_LINK.md >/dev/null 2>&1); then
  echo "FAIL: broken relative link was not rejected" >&2
  exit 1
else
  echo "PASS: broken relative link rejected"
fi

cat >"$T/pkg/.agent/skills/demo/BAD_PATH.md" <<'MD'
# Bad Path
Entry point: `src/bot.js`
MD

if (cd "$T" && bash "$CHECK" --root pkg pkg/.agent/skills/demo/BAD_PATH.md >/dev/null 2>&1); then
  echo "FAIL: missing backticked path was not rejected" >&2
  exit 1
else
  echo "PASS: missing backticked path rejected"
fi
