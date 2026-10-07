#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

# Hermetic unit and integration tests for watch-pr.sh:
# Uses a mock gh binary and scratch git repositories to verify
# check parsing, failure diagnosis, timeout limits, and post-merge pipeline verification.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNDER_TEST="${1:-${HERE}/watch-pr.sh}"
[ -f "${UNDER_TEST}" ] || UNDER_TEST="${HERE}/watch-pr.sh"
[ -f "${UNDER_TEST}" ] || UNDER_TEST="tools/watch-pr/watch-pr.sh"
[ -f "${UNDER_TEST}" ] || { echo "cannot find watch-pr.sh" >&2; exit 1; }

PASS=0; FAIL=0
check() {
  if [ "$2" = "0" ]; then printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1))
  else printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); fi
}

echo "watch-pr_test:"

# --- 1. syntax ---
bash -n "${UNDER_TEST}" 2>/dev/null; check "script parses cleanly" "$?"

# --- 2. JSON check parser unit tests ---
# Source without executing main
# shellcheck source=/dev/null
source "${UNDER_TEST}"

all_green='[
  {"name":"CI","state":"SUCCESS","bucket":"pass","workflow":"ci","link":"https://ci.run/1"},
  {"name":"lint","state":"SUCCESS","bucket":"pass","workflow":"lint","link":"https://ci.run/2"}
]'
res=$(parse_checks_json "$all_green")
stats=$(echo "$res" | head -n1)
check "parse_checks_json: all green produces 2:0:0:0" "$([ "$stats" = "2:0:0:0" ] && echo 0 || echo 1)"

one_failed='[
  {"name":"unit-test","state":"FAILURE","bucket":"fail","workflow":"ci","link":"https://ci.run/99"}
]'
res=$(parse_checks_json "$one_failed")
stats=$(echo "$res" | head -n1)
failed_item=$(echo "$res" | grep "^FAILED_ITEM:" || true)
check "parse_checks_json: failure produces 0:0:0:1" "$([ "$stats" = "0:0:0:1" ] && echo 0 || echo 1)"
check "parse_checks_json: failure includes FAILED_ITEM details" "$([ -n "$failed_item" ] && echo 0 || echo 1)"

pending_and_skipped='[
  {"name":"delivery","state":"SKIPPED","bucket":"skipping","workflow":"delivery","link":""},
  {"name":"integration","state":"IN_PROGRESS","bucket":"pending","workflow":"ci","link":""}
]'
res=$(parse_checks_json "$pending_and_skipped")
stats=$(echo "$res" | head -n1)
check "parse_checks_json: pending and skipped produces 0:1:1:0" "$([ "$stats" = "0:1:1:0" ] && echo 0 || echo 1)"

# --- 3. Argument validation ---
rc=0
out=$(bash "${UNDER_TEST}" 2>&1) || rc=$?
check "watch-pr with no arguments exits 3" "$([ "$rc" = "3" ] && echo 0 || echo 1)"

rc=0
out=$(bash "${UNDER_TEST}" --unrecognized-flag 2>&1) || rc=$?
check "watch-pr with unknown flag exits 3" "$([ "$rc" = "3" ] && echo 0 || echo 1)"

rc=0
out=$(bash "${UNDER_TEST}" --help 2>&1) || rc=$?
check "watch-pr --help exits 0" "$([ "$rc" = "0" ] && echo 0 || echo 1)"

# --- 4. Hermetic integration tests with scratch git repo and mock gh ---
new_repo() {
  local r
  r="$(mktemp -d)"
  (
    cd "${r}" || exit 1
    git init -q -b main
    git config user.email t@t; git config user.name t
    echo base > f.txt; git add -A; git commit -qm base
    # Set up origin/main ref
    git update-ref refs/remotes/origin/main refs/heads/main
  ) >/dev/null 2>&1
  printf '%s' "${r}"
}

# Test 4a: Success path (checks pass, PR merges, post-merge green)
repo="$(new_repo)"; bin="$(mktemp -d)"
mkdir -p "${repo}/tools/pipeline-status"
cat > "${repo}/tools/pipeline-status/pipeline-status.sh" << 'EOF'
#!/usr/bin/env bash
echo "All post-merge workflows passed"
exit 0
EOF
chmod +x "${repo}/tools/pipeline-status/pipeline-status.sh"

cat > "${bin}/gh" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *"pr view 42"*"state,mergeStateStatus,mergeCommit"*)
    echo '{"state":"MERGED","mergeStateStatus":"CLEAN","mergeCommit":{"oid":"0123456789abcdef0123456789abcdef01234567"}}'
    ;;
  *"pr checks 42"*)
    echo '[{"name":"CI","state":"SUCCESS","bucket":"pass","workflow":"ci","link":"https://ci.run/1"}]'
    ;;
  *)
    echo '{}'
    ;;
esac
EOF
chmod +x "${bin}/gh"

out=$(cd "${repo}" && BUILD_WORKSPACE_DIRECTORY="${repo}" GH_TOKEN="test-token" PATH="${bin}:${PATH}" \
      bash "${UNDER_TEST}" 42 2>&1); rc=$?
check "success path exits 0" "$([ "$rc" = "0" ] && echo 0 || echo 1)"
case "${out}" in *GREEN*) check "...and confirms green post-merge pipeline" 0 ;; *) check "...and confirms green post-merge pipeline" 1 ;; esac
rm -rf "${repo}" "${bin}"

# Test 4b: Check failure diagnostics
repo="$(new_repo)"; bin="$(mktemp -d)"
cat > "${bin}/gh" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *"pr view 42"*"state,mergeStateStatus,mergeCommit"*)
    echo '{"state":"OPEN","mergeStateStatus":"BLOCKED","mergeCommit":null}'
    ;;
  *"pr checks 42"*)
    echo '[{"name":"integration-test","state":"FAILURE","bucket":"fail","workflow":"ci","link":"https://github.com/runs/999"}]'
    ;;
  *"run view 999"*)
    echo "ERROR: integration test failure on line 42"
    ;;
  *)
    echo '{}'
    ;;
esac
EOF
chmod +x "${bin}/gh"

out=$(cd "${repo}" && BUILD_WORKSPACE_DIRECTORY="${repo}" GH_TOKEN="test-token" PATH="${bin}:${PATH}" \
      bash "${UNDER_TEST}" 42 2>&1); rc=$?
check "check failure exits 1" "$([ "$rc" = "1" ] && echo 0 || echo 1)"
case "${out}" in *integration-test*) check "...and outputs failing check name" 0 ;; *) check "...and outputs failing check name" 1 ;; esac
rm -rf "${repo}" "${bin}"

# Test 4c: Timeout handling
repo="$(new_repo)"; bin="$(mktemp -d)"
cat > "${bin}/gh" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *"pr view 42"*"state,mergeStateStatus,mergeCommit"*)
    echo '{"state":"OPEN","mergeStateStatus":"BLOCKED","mergeCommit":null}'
    ;;
  *"pr checks 42"*)
    echo '[{"name":"long-running-job","state":"IN_PROGRESS","bucket":"pending","workflow":"ci","link":""}]'
    ;;
  *)
    echo '{}'
    ;;
esac
EOF
chmod +x "${bin}/gh"

out=$(cd "${repo}" && BUILD_WORKSPACE_DIRECTORY="${repo}" GH_TOKEN="test-token" PATH="${bin}:${PATH}" \
      bash "${UNDER_TEST}" 42 --timeout 1 --interval 1 2>&1); rc=$?
check "timeout exits 2" "$([ "$rc" = "2" ] && echo 0 || echo 1)"
case "${out}" in *timed\ out*) check "...and reports timeout message" 0 ;; *) check "...and reports timeout message" 1 ;; esac
rm -rf "${repo}" "${bin}"

# Test 4d: Fallback detection of squashed commit on origin/main
repo="$(new_repo)"; bin="$(mktemp -d)"
(
  cd "${repo}" || exit 1
  echo change > f.txt
  git add -A
  git commit -qm "feat: landed commit (#42)"
  git update-ref refs/remotes/origin/main refs/heads/main
) >/dev/null 2>&1

# Mock gh fails completely
cat > "${bin}/gh" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${bin}/gh"

out=$(cd "${repo}" && BUILD_WORKSPACE_DIRECTORY="${repo}" GH_TOKEN="test-token" PATH="${bin}:${PATH}" \
      bash "${UNDER_TEST}" 42 --skip-post-merge 2>&1); rc=$?
check "fallback detects squashed commit in git log when gh fails" "$([ "$rc" = "0" ] && echo 0 || echo 1)"
rm -rf "${repo}" "${bin}"

echo
if [ "${FAIL}" -ne 0 ]; then
  printf '\033[31mFAIL\033[0m — %d passed, %d failed\n' "${PASS}" "${FAIL}"; exit 1
fi
printf '\033[32mPASS\033[0m — %d passed\n' "${PASS}"
exit 0
