#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
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
# Hermetic parity test for .design-sync/{inject-reference-fonts.sh,prepare.sh}
# and tools/test-mcp-slack-e2e.sh vs their Rust ports in //tools/design-sync.

set -uo pipefail

SH_INJECT="${1:?missing inject-reference-fonts.sh}"
RS_INJECT="${2:?missing :inject_reference_fonts}"
SH_PREPARE="${3:?missing prepare.sh}"
RS_PREPARE="${4:?missing :prepare}"
SH_SLACK="${5:?missing test-mcp-slack-e2e.sh}"
RS_SLACK="${6:?missing :test_mcp_slack_e2e}"

for var in SH_INJECT RS_INJECT SH_PREPARE RS_PREPARE SH_SLACK RS_SLACK; do
  eval "val=\${${var}}"
  case "${val}" in /*) ;; *) eval "${var}=${PWD}/${val}" ;; esac
done

if [ -n "${JQ_BIN:-}" ]; then
  case "${JQ_BIN}" in /*) ;; *) JQ_BIN="${PWD}/${JQ_BIN}" ;; esac
  export PATH="$(dirname "${JQ_BIN}"):${PATH}"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

pass=0
fail=0

compare_runs() {
  local label="$1"
  local sh_cwd="$2"
  local rs_cwd="$3"
  local sh_bin="$4"
  local rs_bin="$5"
  shift 5

  (
    cd "${sh_cwd}" &&
    env "$@" "${sh_bin}"
  ) >"${WORK}/sh.stdout" 2>"${WORK}/sh.stderr"
  local sh_rc=$?

  (
    cd "${rs_cwd}" &&
    env "$@" "${rs_bin}"
  ) >"${WORK}/rs.stdout" 2>"${WORK}/rs.stderr"
  local rs_rc=$?

  local ok=1
  diff -u "${WORK}/sh.stdout" "${WORK}/rs.stdout" >"${WORK}/diff.stdout" 2>&1 || ok=0
  diff -u "${WORK}/sh.stderr" "${WORK}/rs.stderr" >"${WORK}/diff.stderr" 2>&1 || ok=0
  [ "${sh_rc}" = "${rs_rc}" ] || ok=0

  if [ "${ok}" -eq 1 ]; then
    echo "PASS: ${label}"
    pass=$((pass + 1))
  else
    echo "FAIL: ${label} (sh_rc=${sh_rc}, rs_rc=${rs_rc})" >&2
    [ -s "${WORK}/diff.stdout" ] && cat "${WORK}/diff.stdout" >&2
    [ -s "${WORK}/diff.stderr" ] && cat "${WORK}/diff.stderr" >&2
    fail=$((fail + 1))
  fi
}

# ─── 1. inject-reference-fonts parity tests ──────────────────────────────────

setup_inject_pair() {
  local name="$1"
  rm -rf "${WORK}/${name}_sh" "${WORK}/${name}_rs"
  for side in sh rs; do
    d="${WORK}/${name}_${side}/.design-sync"
    mkdir -p "${d}/fonts" "${d}/sb-reference"
    cp "${SH_INJECT}" "${d}/inject.sh"
    chmod +x "${d}/inject.sh"
    cp "${RS_INJECT}" "${d}/inject-rs"
    chmod +x "${d}/inject-rs"
    echo "fake-woff2" > "${d}/fonts/IBMPlexSans-Regular.woff2"
    cat > "${d}/fonts.css" <<'EOF'
@font-face {
  font-family: 'IBM Plex Sans';
  src: url('./fonts/IBMPlexSans-Regular.woff2') format('woff2');
}
EOF
    cat > "${d}/sb-reference/iframe.html" <<'EOF'
<!doctype html><html><head><title>Storybook</title></head><body></body></html>
EOF
  done
}

# 1a. Missing sb-reference/iframe.html
setup_inject_pair "inj_no_iframe"
rm -f "${WORK}/inj_no_iframe_sh/.design-sync/sb-reference/iframe.html" \
      "${WORK}/inj_no_iframe_rs/.design-sync/sb-reference/iframe.html"
compare_runs "inject-reference-fonts: missing iframe.html" \
  "${WORK}/inj_no_iframe_sh" "${WORK}/inj_no_iframe_rs" \
  "${WORK}/inj_no_iframe_sh/.design-sync/inject.sh" \
  "${WORK}/inj_no_iframe_rs/.design-sync/inject-rs"

# 1b. Missing referenced font face
setup_inject_pair "inj_missing_face"
for side in sh rs; do
  cat >> "${WORK}/inj_missing_face_${side}/.design-sync/fonts.css" <<'EOF'
@font-face {
  src: url('./fonts/MissingFont.woff2') format('woff2');
}
EOF
done
compare_runs "inject-reference-fonts: missing font face" \
  "${WORK}/inj_missing_face_sh" "${WORK}/inj_missing_face_rs" \
  "${WORK}/inj_missing_face_sh/.design-sync/inject.sh" \
  "${WORK}/inj_missing_face_rs/.design-sync/inject-rs"

# 1c. Fresh injection + verify file contents match
setup_inject_pair "inj_ok"
compare_runs "inject-reference-fonts: fresh injection" \
  "${WORK}/inj_ok_sh" "${WORK}/inj_ok_rs" \
  "${WORK}/inj_ok_sh/.design-sync/inject.sh" \
  "${WORK}/inj_ok_rs/.design-sync/inject-rs"

if ! diff -u "${WORK}/inj_ok_sh/.design-sync/sb-reference/iframe.html" \
             "${WORK}/inj_ok_rs/.design-sync/sb-reference/iframe.html" >/dev/null ||
   ! diff -u "${WORK}/inj_ok_sh/.design-sync/sb-reference/ds-fonts/fonts.css" \
             "${WORK}/inj_ok_rs/.design-sync/sb-reference/ds-fonts/fonts.css" >/dev/null; then
  echo "FAIL: inject-reference-fonts output files differ" >&2
  fail=$((fail + 1))
fi

# 1d. Idempotent re-run when already injected
compare_runs "inject-reference-fonts: already injected" \
  "${WORK}/inj_ok_sh" "${WORK}/inj_ok_rs" \
  "${WORK}/inj_ok_sh/.design-sync/inject.sh" \
  "${WORK}/inj_ok_rs/.design-sync/inject-rs"

# ─── 2. prepare.sh parity tests ──────────────────────────────────────────────

setup_prepare_pair() {
  local name="$1"
  local tsc_rc="$2"
  local css_out="$3"
  rm -rf "${WORK}/${name}_sh" "${WORK}/${name}_rs"
  for side in sh rs; do
    r="${WORK}/${name}_${side}"
    mkdir -p "${r}/.design-sync" \
             "${r}/packages/design-system/dist" \
             "${r}/node_modules/.bin" \
             "${r}/.ds-sync/node_modules/.bin"
    cp "${SH_PREPARE}" "${r}/.design-sync/prepare.sh"
    chmod +x "${r}/.design-sync/prepare.sh"
    cp "${RS_PREPARE}" "${r}/.design-sync/prepare-rs"
    chmod +x "${r}/.design-sync/prepare-rs"
    echo "/* entry */" > "${r}/.design-sync/tailwind-entry.css"
    echo "{}" > "${r}/packages/design-system/tsconfig.json"

    cat > "${r}/node_modules/.bin/tsc" <<EOF
#!/usr/bin/env bash
echo "tsc: \$*"
exit ${tsc_rc}
EOF
    chmod +x "${r}/node_modules/.bin/tsc"

    cat > "${r}/.ds-sync/node_modules/.bin/tailwindcss" <<EOF
#!/usr/bin/env bash
# args: -i <in> -o <out>
printf '%s\n' "${css_out}" > "\$4"
exit 0
EOF
    chmod +x "${r}/.ds-sync/node_modules/.bin/tailwindcss"
  done
}

# 2a. tsc fails
setup_prepare_pair "prep_tsc_fail" 2 ":root {}"
compare_runs "prepare: tsc failure" \
  "${WORK}/prep_tsc_fail_sh" "${WORK}/prep_tsc_fail_rs" \
  "${WORK}/prep_tsc_fail_sh/.design-sync/prepare.sh" \
  "${WORK}/prep_tsc_fail_rs/.design-sync/prepare-rs"

# 2b. Leaked stock Tailwind color fails guard
setup_prepare_pair "prep_leak" 0 ":root { --color-blue-500: #3b82f6; }"
compare_runs "prepare: stock Tailwind colour leak" \
  "${WORK}/prep_leak_sh" "${WORK}/prep_leak_rs" \
  "${WORK}/prep_leak_sh/.design-sync/prepare.sh" \
  "${WORK}/prep_leak_rs/.design-sync/prepare-rs"

# 2c. Clean build succeeds
setup_prepare_pair "prep_ok" 0 ":root { --color-surface-primary: #111; }"
compare_runs "prepare: clean build" \
  "${WORK}/prep_ok_sh" "${WORK}/prep_ok_rs" \
  "${WORK}/prep_ok_sh/.design-sync/prepare.sh" \
  "${WORK}/prep_ok_rs/.design-sync/prepare-rs"

# ─── 3. test-mcp-slack-e2e.sh parity tests ───────────────────────────────────

STUB_BIN="${WORK}/slack_bin"
mkdir -p "${STUB_BIN}"
cat > "${STUB_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
# Inspect arguments to decide what fake response to return
all_args="$*"
case "${all_args}" in
  *".well-known/oauth-protected-resource/mcp"*)
    if [ "${FAKE_DISC_STATUS:-200}" = "200" ]; then
      printf "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"resource\":\"https://mcp-slack.ipv1337.dev/mcp\",\n\"authorization_servers\":[\"https://auth.ipv1337.dev\"]}\n"
    else
      printf "HTTP/1.1 500 Internal Server Error\r\n\r\n"
    fi
    exit 0
    ;;
  *"\"method\": \"initialize\""*)
    if [ "${FAKE_INIT_OK:-1}" = "1" ]; then
      printf 'event: message\ndata: {"jsonrpc":"2.0","id":1,"result":{"serverInfo":{"name":"mcp-slack","version":"2.0.0"}}}\n'
    else
      printf '{"error":"invalid_token"}\n'
    fi
    exit 0
    ;;
  *"\"method\": \"tools/list\""*)
    printf 'event: message\ndata: {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"t1"},{"name":"t2"},{"name":"t3"}]}}\n'
    exit 0
    ;;
  *"\"method\": \"tools/call\""*)
    printf 'event: message\ndata: {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"{\\"channels\\":[{\\"id\\":\\"C1\\"},{\\"id\\":\\"C2\\"}]}"}]}}\n'
    exit 0
    ;;
  *)
    if [ "${FAKE_UNAUTH_STATUS:-401}" = "401" ]; then
      printf "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Bearer resource_metadata=\"https://mcp-slack.ipv1337.dev/.well-known/oauth-protected-resource/mcp\"\r\n\r\n"
    else
      printf "HTTP/1.1 200 OK\r\n\r\n"
    fi
    exit 0
    ;;
esac
EOF
chmod +x "${STUB_BIN}/curl"

SLACK_PATH="${STUB_BIN}:${PATH}"

# 3a. Discovery fails
compare_runs "test-mcp-slack-e2e: discovery endpoint failure" \
  "${WORK}" "${WORK}" \
  "${SH_SLACK}" "${RS_SLACK}" \
  PATH="${SLACK_PATH}" FAKE_DISC_STATUS="500" MCP_TOKEN=""

# 3b. Unauthenticated check fails (returns 200 instead of 401)
compare_runs "test-mcp-slack-e2e: unauthenticated 401 check failure" \
  "${WORK}" "${WORK}" \
  "${SH_SLACK}" "${RS_SLACK}" \
  PATH="${SLACK_PATH}" FAKE_DISC_STATUS="200" FAKE_UNAUTH_STATUS="200" MCP_TOKEN=""

# 3c. Unauthenticated pass (no MCP_TOKEN)
compare_runs "test-mcp-slack-e2e: base unauthenticated pass without token" \
  "${WORK}" "${WORK}" \
  "${SH_SLACK}" "${RS_SLACK}" \
  PATH="${SLACK_PATH}" FAKE_DISC_STATUS="200" FAKE_UNAUTH_STATUS="401" MCP_TOKEN=""

# 3d. Authenticated initialize fails
compare_runs "test-mcp-slack-e2e: authenticated initialize failure" \
  "${WORK}" "${WORK}" \
  "${SH_SLACK}" "${RS_SLACK}" \
  PATH="${SLACK_PATH}" FAKE_DISC_STATUS="200" FAKE_UNAUTH_STATUS="401" FAKE_INIT_OK="0" MCP_TOKEN="test-jwt"

# 3e. Full authenticated flow passes
compare_runs "test-mcp-slack-e2e: full authenticated flow pass" \
  "${WORK}" "${WORK}" \
  "${SH_SLACK}" "${RS_SLACK}" \
  PATH="${SLACK_PATH}" FAKE_DISC_STATUS="200" FAKE_UNAUTH_STATUS="401" FAKE_INIT_OK="1" MCP_TOKEN="test-jwt"

echo ""
echo "Summary: ${pass} passed, ${fail} failed"
[ "${fail}" -eq 0 ]
