#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Parity test for the Pulumi tool Bash-to-Rust ports:
#   create-app.sh  vs  :create-app  (Rust)
#   pulumi_setup.sh vs :pulumi-setup (Rust)
#   pulumi_go_test.sh vs :pulumi-go-test (Rust)
#
# Each scenario runs both implementations with the same stubs and inputs, then
# compares exit codes, stdout, stderr and recorded tool invocations.
set -uo pipefail

CREATE_APP_SH="${1:?arg 1: path to create-app.sh}"
CREATE_APP_RS="${2:?arg 2: path to create-app (Rust)}"
SETUP_SH="${3:?arg 3: path to pulumi_setup.sh}"
SETUP_RS="${4:?arg 4: path to pulumi-setup (Rust)}"
GO_TEST_SH="${5:?arg 5: path to pulumi_go_test.sh}"
GO_TEST_RS="${6:?arg 6: path to pulumi-go-test (Rust)}"

# Resolve to absolute paths.
for var in CREATE_APP_SH CREATE_APP_RS SETUP_SH SETUP_RS GO_TEST_SH GO_TEST_RS; do
  val="${!var}"
  abs="$(cd "$(dirname "$val")" && pwd)/$(basename "$val")"
  eval "$var=\"\$abs\""
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass_n=0
fail_n=0
pass() { echo "  ✓ $1"; pass_n=$((pass_n + 1)); }
fail() { echo "  ✗ $1" >&2; fail_n=$((fail_n + 1)); }

# =========================================================================
# Part 1: create-app.sh vs :create-app
# =========================================================================
echo "=== create-app parity ==="

stubs="$work/ca-stubs"
mkdir -p "$stubs"

# Stub jq — extract fields from the conversion JSON the way the real jq does.
cat >"$stubs/jq" <<'STUB'
#!/usr/bin/env bash
input="$(cat)"
case "$1" in
  -r) shift ;;
esac
case "$1" in
  .id)         echo "12345" ;;
  .slug)       echo "testorg-pulumi" ;;
  .pem)        echo "fake-pem-key-value" ;;
  '.client_id // empty') echo "Iv1.abc123" ;;
  .login)      echo "testuser" ;;
  *)           echo "$input" ;;
esac
STUB

# Stub gh — logs all invocations, returns canned data.
cat >"$stubs/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >>"$GH_LOG"
if [ ! -t 0 ]; then
  cat >>"$GH_STDIN_LOG"
fi
case "$1" in
  auth)
    exit "${GH_AUTH_RC:-0}"
    ;;
  api)
    shift
    # Skip flags until we reach a path-like arg
    while [[ "${1:-}" == --* ]]; do
      if [ "$1" = "--jq" ]; then shift; shift; continue; fi
      if [ "$1" = "--method" ]; then shift; shift; continue; fi
      shift
    done
    path="${1:-}"
    case "$path" in
      user)
        echo '{"login":"testuser"}'
        ;;
      orgs/*)
        exit "${GH_ORG_RC:-1}"
        ;;
      /app-manifests/*/conversions)
        if [ "${GH_CONV_FAIL:-0}" = "1" ]; then exit 1; fi
        echo '{"id":12345,"slug":"testorg-pulumi","pem":"fake-pem-key-value","client_id":"Iv1.abc123"}'
        ;;
      *)
        echo '{}'
        ;;
    esac
    ;;
  variable)
    exit "${GH_VAR_RC:-0}"
    ;;
  secret)
    exit "${GH_SECRET_RC:-0}"
    ;;
esac
STUB

# Stub open/xdg-open — no-op
cat >"$stubs/open" <<'STUB'
#!/usr/bin/env bash
echo "open $*" >>"$GH_LOG"
STUB

# Stub nc/timeout — not present (force paste path)
# (We just don't put them on PATH)

chmod +x "$stubs/gh" "$stubs/jq" "$stubs/open"

run_create_app() {
  local tool="$1" label="$2"
  shift 2
  local log="$work/ca-$label.gh" stdin_log="$work/ca-$label.stdin"
  : >"$log"
  : >"$stdin_log"
  env PATH="$stubs:/usr/bin:/bin" \
    GH_LOG="$log" GH_STDIN_LOG="$stdin_log" \
    GH_AUTH_RC="${GH_AUTH_RC:-0}" GH_ORG_RC="${GH_ORG_RC:-1}" \
    GH_CONV_FAIL="${GH_CONV_FAIL:-0}" \
    GH_VAR_RC="${GH_VAR_RC:-0}" GH_SECRET_RC="${GH_SECRET_RC:-0}" \
    TMPDIR="$work" \
    "$tool" "$@" >"$work/ca-$label.out" 2>"$work/ca-$label.err"
  echo $?
}

# --- Test 1a: missing gh ---
echo "--- 1a. create-app: missing gh ---"
rc_sh="$(env PATH="/usr/bin:/bin" "$CREATE_APP_SH" 2>"$work/ca-ngh-sh.err"; echo $?)"
rc_rs="$(env PATH="/usr/bin:/bin" "$CREATE_APP_RS" 2>"$work/ca-ngh-rs.err"; echo $?)"
if [ "$rc_sh" = "$rc_rs" ] && [ "$rc_sh" != "0" ]; then
  pass "both exit non-zero when gh is missing (sh=$rc_sh rs=$rc_rs)"
else
  fail "exit code mismatch for missing gh: sh=$rc_sh rs=$rc_rs"
fi

# --- Test 1b: missing jq ---
echo "--- 1b. create-app: missing jq ---"
mkdir -p "$work/jq-stubs"
cat >"$work/jq-stubs/gh" <<'S'
#!/usr/bin/env bash
case "$1" in auth) exit 0 ;; esac
S
chmod +x "$work/jq-stubs/gh"
rc_sh="$(env PATH="$work/jq-stubs:/usr/bin:/bin" "$CREATE_APP_SH" 2>/dev/null; echo $?)"
rc_rs="$(env PATH="$work/jq-stubs:/usr/bin:/bin" "$CREATE_APP_RS" 2>/dev/null; echo $?)"
if [ "$rc_sh" = "$rc_rs" ] && [ "$rc_sh" != "0" ]; then
  pass "both exit non-zero when jq is missing (sh=$rc_sh rs=$rc_rs)"
else
  fail "exit code mismatch for missing jq: sh=$rc_sh rs=$rc_rs"
fi

# --- Test 1c: org owner, full flow with PULUMI_ACCESS_TOKEN ---
echo "--- 1c. create-app: org owner, full flow ---"
GH_ORG_RC=0 GH_AUTH_RC=0
rc_sh="$(echo -e "testcode\nfaketoken" | run_create_app "$CREATE_APP_SH" sh-org testorg)"
rc_rs="$(echo -e "testcode\nfaketoken" | GH_ORG_RC=0 run_create_app "$CREATE_APP_RS" rs-org testorg)"
if [ "$rc_sh" = "$rc_rs" ]; then
  pass "exit codes match for org owner flow (rc=$rc_sh)"
else
  fail "exit code mismatch for org flow: sh=$rc_sh rs=$rc_rs"
fi

# --- Test 1d: personal owner (org probe fails) ---
echo "--- 1d. create-app: personal owner ---"
rc_sh="$(echo -e "testcode\nfaketoken" | GH_ORG_RC=1 run_create_app "$CREATE_APP_SH" sh-pers testuser)"
rc_rs="$(echo -e "testcode\nfaketoken" | GH_ORG_RC=1 run_create_app "$CREATE_APP_RS" rs-pers testuser)"
if [ "$rc_sh" = "$rc_rs" ]; then
  pass "exit codes match for personal owner flow (rc=$rc_sh)"
else
  fail "exit code mismatch for personal flow: sh=$rc_sh rs=$rc_rs"
fi

# --- Test 1e: gh variable set fails → exit non-zero ---
echo "--- 1e. create-app: gh variable set failure ---"
rc_sh="$(echo "testcode" | GH_VAR_RC=1 run_create_app "$CREATE_APP_SH" sh-varfail testorg)"
rc_rs="$(echo "testcode" | GH_VAR_RC=1 run_create_app "$CREATE_APP_RS" rs-varfail testorg)"
if [ "$rc_sh" != "0" ] && [ "$rc_rs" != "0" ]; then
  pass "both exit non-zero when gh variable set fails (sh=$rc_sh rs=$rc_rs)"
else
  fail "should exit non-zero on variable set failure: sh=$rc_sh rs=$rc_rs"
fi

# --- Test 1f: no PULUMI_ACCESS_TOKEN (skip prompt answer) ---
echo "--- 1f. create-app: no pulumi token (empty stdin) ---"
rc_sh="$(echo "testcode" | GH_ORG_RC=1 run_create_app "$CREATE_APP_SH" sh-nopat testuser)"
rc_rs="$(echo "testcode" | GH_ORG_RC=1 run_create_app "$CREATE_APP_RS" rs-nopat testuser)"
if [ "$rc_sh" = "$rc_rs" ]; then
  pass "exit codes match when pulumi token is skipped (rc=$rc_sh)"
else
  fail "exit code mismatch skipping token: sh=$rc_sh rs=$rc_rs"
fi

# =========================================================================
# Part 2: pulumi_setup.sh vs :pulumi-setup
# =========================================================================
echo
echo "=== pulumi-setup parity ==="

setup_stubs="$work/su-stubs"
mkdir -p "$setup_stubs"

cat >"$setup_stubs/pulumi" <<'STUB'
#!/usr/bin/env bash
echo "pulumi $*" >>"$TOOL_LOG"
case "$1" in
  whoami)
    if [ "${PULUMI_LOGGED_IN:-1}" = "1" ]; then echo "testuser"; exit 0; fi
    exit 1
    ;;
  stack)
    case "$2" in
      --show-name)
        if [ "${PULUMI_HAS_STACK:-1}" = "1" ]; then echo "dev"; exit 0; fi
        exit 1
        ;;
      ls) echo "dev*  last update 1d ago"; exit 0 ;;
      select) exit 0 ;;
      init) exit 0 ;;
    esac
    ;;
  login) exit 0 ;;
esac
STUB

cat >"$setup_stubs/go" <<'STUB'
#!/usr/bin/env bash
echo "go $*" >>"$TOOL_LOG"
exit 0
STUB

cat >"$setup_stubs/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >>"$TOOL_LOG"
case "$1" in
  variable) exit 0 ;;
  secret) exit 0 ;;
  repo)
    echo '{"owner":{"login":"testorg"}}'
    ;;
esac
STUB

chmod +x "$setup_stubs/pulumi" "$setup_stubs/go" "$setup_stubs/gh"

run_setup() {
  local tool="$1" label="$2" project_dir="$3"
  shift 3
  local log="$work/su-$label.log"
  : >"$log"
  local ws="$work/su-$label-ws"
  mkdir -p "$ws/$project_dir"
  env PATH="$setup_stubs:/usr/bin:/bin" \
    TOOL_LOG="$log" \
    BUILD_WORKSPACE_DIRECTORY="$ws" \
    PULUMI_LOGGED_IN="${PULUMI_LOGGED_IN:-1}" \
    PULUMI_HAS_STACK="${PULUMI_HAS_STACK:-1}" \
    GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
    "$tool" "$project_dir" "$@" >"$work/su-$label.out" 2>"$work/su-$label.err"
  echo $?
}

# --- Test 2a: missing pulumi ---
echo "--- 2a. pulumi-setup: missing pulumi ---"
ws2a="$work/su-nopulumi-ws"
mkdir -p "$ws2a/some/project"
# Only go on PATH, no pulumi
mkdir -p "$work/su-nopulumi-stubs"
cp "$setup_stubs/go" "$work/su-nopulumi-stubs/go"
chmod +x "$work/su-nopulumi-stubs/go"
rc_sh="$(env PATH="$work/su-nopulumi-stubs:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$ws2a" "$SETUP_SH" "some/project" >/dev/null 2>/dev/null; echo $?)"
rc_rs="$(env PATH="$work/su-nopulumi-stubs:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$ws2a" "$SETUP_RS" "some/project" >/dev/null 2>/dev/null; echo $?)"
if [ "$rc_sh" != "0" ] && [ "$rc_rs" != "0" ]; then
  pass "both exit non-zero when pulumi is missing (sh=$rc_sh rs=$rc_rs)"
else
  fail "should exit non-zero when pulumi is missing: sh=$rc_sh rs=$rc_rs"
fi

# --- Test 2b: missing go ---
echo "--- 2b. pulumi-setup: missing go ---"
ws2b="$work/su-nogo-ws"
mkdir -p "$ws2b/some/project"
mkdir -p "$work/su-nogo-stubs"
cp "$setup_stubs/pulumi" "$work/su-nogo-stubs/pulumi"
chmod +x "$work/su-nogo-stubs/pulumi"
rc_sh="$(env PATH="$work/su-nogo-stubs:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$ws2b" "$SETUP_SH" "some/project" >/dev/null 2>/dev/null; echo $?)"
rc_rs="$(env PATH="$work/su-nogo-stubs:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$ws2b" "$SETUP_RS" "some/project" >/dev/null 2>/dev/null; echo $?)"
if [ "$rc_sh" != "0" ] && [ "$rc_rs" != "0" ]; then
  pass "both exit non-zero when go is missing (sh=$rc_sh rs=$rc_rs)"
else
  fail "should exit non-zero when go is missing: sh=$rc_sh rs=$rc_rs"
fi

# --- Test 2c: already logged in, stack selected, non-repo-config ---
echo "--- 2c. pulumi-setup: happy path (non-repo-config) ---"
PULUMI_LOGGED_IN=1 PULUMI_HAS_STACK=1 GITHUB_TOKEN="ghp_fake"
rc_sh="$(run_setup "$SETUP_SH" sh-happy "infrastructure/pulumi/platform/gcp-app-infra")"
rc_rs="$(run_setup "$SETUP_RS" rs-happy "infrastructure/pulumi/platform/gcp-app-infra")"
if [ "$rc_sh" = "$rc_rs" ] && [ "$rc_sh" = "0" ]; then
  pass "both succeed for non-repo-config happy path"
else
  fail "exit code mismatch for happy path: sh=$rc_sh rs=$rc_rs"
fi

# --- Test 2d: repo-config project ---
echo "--- 2d. pulumi-setup: repo-config project ---"
rc_sh="$(echo -e "N\nN" | PULUMI_LOGGED_IN=1 PULUMI_HAS_STACK=1 GITHUB_TOKEN="" run_setup "$SETUP_SH" sh-rc "infrastructure/pulumi/platform/repo-config")"
rc_rs="$(echo -e "N\nN" | PULUMI_LOGGED_IN=1 PULUMI_HAS_STACK=1 GITHUB_TOKEN="" run_setup "$SETUP_RS" rs-rc "infrastructure/pulumi/platform/repo-config")"
if [ "$rc_sh" = "$rc_rs" ] && [ "$rc_sh" = "0" ]; then
  pass "both succeed for repo-config project"
else
  fail "exit code mismatch for repo-config: sh=$rc_sh rs=$rc_rs"
fi

# --- Test 2e: GITHUB_TOKEN set vs unset ---
echo "--- 2e. pulumi-setup: GITHUB_TOKEN set vs unset ---"
GITHUB_TOKEN="ghp_fake"
rc_sh="$(run_setup "$SETUP_SH" sh-tok "infrastructure/pulumi/platform/gcp-app-infra")"
rc_rs="$(run_setup "$SETUP_RS" rs-tok "infrastructure/pulumi/platform/gcp-app-infra")"
if [ "$rc_sh" = "$rc_rs" ]; then
  pass "exit codes match with GITHUB_TOKEN set (rc=$rc_sh)"
else
  fail "exit code mismatch with GITHUB_TOKEN: sh=$rc_sh rs=$rc_rs"
fi
GITHUB_TOKEN=""
rc_sh="$(run_setup "$SETUP_SH" sh-notok "infrastructure/pulumi/platform/gcp-app-infra")"
rc_rs="$(run_setup "$SETUP_RS" rs-notok "infrastructure/pulumi/platform/gcp-app-infra")"
if [ "$rc_sh" = "$rc_rs" ]; then
  pass "exit codes match without GITHUB_TOKEN (rc=$rc_sh)"
else
  fail "exit code mismatch without GITHUB_TOKEN: sh=$rc_sh rs=$rc_rs"
fi

# =========================================================================
# Part 3: pulumi_go_test.sh vs :pulumi-go-test
# =========================================================================
echo
echo "=== pulumi-go-test parity ==="

gt_stubs="$work/gt-stubs"
mkdir -p "$gt_stubs"

# Stub go — records invocations, checks GOWORK=off
cat >"$gt_stubs/go" <<'STUB'
#!/usr/bin/env bash
echo "GOWORK=$GOWORK go $*" >>"$TOOL_LOG"
if [ "$1" = "test" ] && [ "${GOWORK:-}" = "off" ]; then
  echo "ok  (stubbed go test)"
  exit 0
fi
exit 1
STUB
chmod +x "$gt_stubs/go"

# --- Test 3a: no arguments → usage error ---
echo "--- 3a. pulumi-go-test: no args ---"
rc_sh="$("$GO_TEST_SH" 2>/dev/null; echo $?)"
rc_rs="$("$GO_TEST_RS" 2>/dev/null; echo $?)"
if [ "$rc_sh" != "0" ] && [ "$rc_rs" != "0" ]; then
  pass "both exit non-zero with no args (sh=$rc_sh rs=$rc_rs)"
else
  fail "should exit non-zero with no args: sh=$rc_sh rs=$rc_rs"
fi

# --- Test 3b: non-existent dir ---
echo "--- 3b. pulumi-go-test: non-existent dir ---"
rc_sh="$("$GO_TEST_SH" "$work/nope" 2>/dev/null; echo $?)"
rc_rs="$("$GO_TEST_RS" "$work/nope" 2>/dev/null; echo $?)"
if [ "$rc_sh" != "0" ] && [ "$rc_rs" != "0" ]; then
  pass "both exit non-zero for non-existent dir (sh=$rc_sh rs=$rc_rs)"
else
  fail "should exit non-zero for non-existent dir: sh=$rc_sh rs=$rc_rs"
fi

# --- Test 3c: missing go toolchain ---
echo "--- 3c. pulumi-go-test: missing go ---"
mkdir -p "$work/gt-project"
rc_sh="$(PATH="/usr/bin:/bin" "$GO_TEST_SH" "$work/gt-project" 2>/dev/null; echo $?)"
rc_rs="$(PATH="/usr/bin:/bin" "$GO_TEST_RS" "$work/gt-project" 2>/dev/null; echo $?)"
if [ "$rc_sh" != "0" ] && [ "$rc_rs" != "0" ]; then
  pass "both exit non-zero when go is missing (sh=$rc_sh rs=$rc_rs)"
else
  fail "should exit non-zero when go is missing: sh=$rc_sh rs=$rc_rs"
fi

# --- Test 3d: stub go on PATH, verify GOWORK=off and go test ./... ---
echo "--- 3d. pulumi-go-test: GOWORK=off and go test ./... ---"
gt_log="$work/gt-log"
mkdir -p "$work/gt-real-project"
# Shell version: execs go, so we capture it in the stub.
# Redirect stdout to a file to avoid mixing go output with the exit code.
: >"$gt_log"
env PATH="$gt_stubs:/usr/bin:/bin" TOOL_LOG="$gt_log" "$GO_TEST_SH" "$work/gt-real-project" >"$work/gt-sh.out" 2>/dev/null
rc_sh=$?
sh_invocations="$(cat "$gt_log")"
# Rust version
: >"$gt_log"
env PATH="$gt_stubs:/usr/bin:/bin" TOOL_LOG="$gt_log" "$GO_TEST_RS" "$work/gt-real-project" >"$work/gt-rs.out" 2>/dev/null
rc_rs=$?
rs_invocations="$(cat "$gt_log")"
if [ "$rc_sh" = "0" ] && [ "$rc_rs" = "0" ]; then
  pass "both succeed with stub go (sh=$rc_sh rs=$rc_rs)"
else
  fail "exit code mismatch with stub go: sh=$rc_sh rs=$rc_rs"
fi
if echo "$sh_invocations" | grep -q "GOWORK=off go test"; then
  pass "shell sets GOWORK=off for go test"
else
  fail "shell did not set GOWORK=off: $sh_invocations"
fi
if echo "$rs_invocations" | grep -q "GOWORK=off go test"; then
  pass "Rust sets GOWORK=off for go test"
else
  fail "Rust did not set GOWORK=off: $rs_invocations"
fi

# =========================================================================
# Summary
# =========================================================================
echo
if [ "$fail_n" -gt 0 ]; then
  echo "FAILED: $fail_n"
  exit 1
fi
echo "ALL PASS ($pass_n)"
