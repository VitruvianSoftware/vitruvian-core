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

# Hermetic guard for tools/ci/resolve-deploy-base.sh (#1351). Fake `gh` (no
# network, no credentials — mirrors tabula-deploy-preflight_test.sh's
# fake-gcloud pattern). Pins the FAIL-OPEN invariant: base_sha is empty on ANY
# lookup problem, so the caller falls back to github.event.before instead of
# ever fabricating a wrong diff base.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/resolve-deploy-base.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

# fake gh: ignores its args (the script under test always passes the same
# shape); prints $FAKE_GH_OUT to stdout, or simulates a failure.
cat > "$work/fake-gh" <<'EOF'
#!/usr/bin/env bash
if [ "${FAKE_GH_RC:-0}" != "0" ]; then
  echo "gh: HTTP 502 (something went wrong)" >&2
  exit "${FAKE_GH_RC}"
fi
printf '%s' "${FAKE_GH_OUT:-}"
EOF
chmod +x "$work/fake-gh"

# run <env...> — prints the base_sha= value written to $GITHUB_OUTPUT.
# GITHUB_REPOSITORY is cleared by default (a real GH Actions runner always
# sets it ambiently, and `env` overrides only the vars it lists) so a test
# that overrides REPO="" here would still see an empty fallback; "$@" can
# still re-set it explicitly if a future test needs to.
run() {
  local out="$work/out"; : > "$out"
  env GITHUB_OUTPUT="$out" GH_BIN="$work/fake-gh" GITHUB_REPOSITORY="" \
    REPO="owner/repo" WORKFLOW_FILE="some-deploy.yaml" "$@" \
    bash "$SCRIPT" >"$work/stdout" 2>"$work/stderr"
  sed -n 's/^base_sha=//p' "$out"
}

expect() { # <label> <want-sha> [env...]
  local label="$1" want="$2"; shift 2
  local got; got="$(run "$@")"
  if [ "$got" = "$want" ]; then pass "$label (base_sha='$got')"; else
    fail "$label — got '$got', want '$want'"
    sed 's/^/      stderr: /' "$work/stderr" >&2
  fi
}

echo "--- happy path ---"
expect "resolves the last successful push run's sha" "abc123def456" FAKE_GH_OUT=abc123def456

echo "--- fail-open paths (every one must yield an EMPTY base_sha) ---"
expect "no prior successful run (first push ever)" "" FAKE_GH_OUT=""
expect "gh error" "" FAKE_GH_RC=1

echo "--- gh error also warns, so a persistently broken lookup is audible ---"
run FAKE_GH_RC=1 >/dev/null
if grep -q "::warning title=deploy-gate-durable-base-fallback::" "$work/stdout"; then
  pass "gh error emits a titled warning annotation"
else
  fail "gh error did not emit the expected warning annotation"
fi

echo "--- REPO resolution ---"
out="$work/out3"; : > "$out"
# GITHUB_REPOSITORY must be explicitly cleared, not just REPO: every real GH
# Actions runner sets it ambiently, and `env` only OVERRIDES the listed vars,
# it does not clear the rest of the inherited environment. Without this the
# script's own fallback to GITHUB_REPOSITORY silently picks up the runner's
# real value and this test passes locally but fails in CI.
env GITHUB_OUTPUT="$out" GH_BIN="$work/fake-gh" WORKFLOW_FILE="some-deploy.yaml" REPO="" GITHUB_REPOSITORY="" \
  bash "$SCRIPT" >"$work/stdout3" 2>"$work/stderr3"
got="$(sed -n 's/^base_sha=//p' "$out")"
if [ "$got" = "" ] && grep -q "REPO/GITHUB_REPOSITORY unset" "$work/stdout3"; then
  pass "REPO and GITHUB_REPOSITORY both unset fails open with the right reason"
else
  fail "REPO/GITHUB_REPOSITORY unset — got base_sha='$got', expected empty with the unset reason"
fi

echo "--- required env is a caller bug, not a fail-open case ---"
env GITHUB_OUTPUT="$work/out4" GH_BIN="$work/fake-gh" REPO="owner/repo" \
  bash "$SCRIPT" >/dev/null 2>"$work/stderr4"
rc=$?
if [ "$rc" -ne 0 ] && grep -q "WORKFLOW_FILE must be set" "$work/stderr4"; then
  pass "missing WORKFLOW_FILE exits non-zero instead of silently emitting empty"
else
  fail "missing WORKFLOW_FILE — expected non-zero exit with the WORKFLOW_FILE message, got rc=$rc"
fi

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails" >&2; exit 1; fi
echo "ALL PASS"
