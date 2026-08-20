#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Tests for delivery-drift.sh. Stubs `gh` and `bazel` (there is no GitHub or
# Bazel in a hermetic test) but drives the REAL tools/ci/deploy-affected.sh, so
# the property under test -- "the detector and the decider agree about what
# affected means" -- is actually exercised rather than mocked away.
set -uo pipefail

SCRIPT="${1:?usage: delivery-drift_test.sh <path to delivery-drift.sh> <path to deploy-affected.sh>}"
ENGINE="${2:?missing deploy-affected.sh}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
ENGINE="$(cd "$(dirname "$ENGINE")" && pwd)/$(basename "$ENGINE")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass_n=0
fail_n=0
pass() {
    echo "  ✓ $1"
    pass_n=$((pass_n + 1))
}
fail() {
    echo "  ✗ $1" >&2
    fail_n=$((fail_n + 1))
}

# --- a real git repo with a real history --------------------------------------
repo="$work/repo"
mkdir -p "$repo/tools/ci" "$repo/oauth-user-inspector/app" "$repo/bazel-bin/oauth-user-inspector/infra/app"
cp "$ENGINE" "$repo/tools/ci/deploy-affected.sh"
cd "$repo"
git init -q .
git config user.email t@t
git config user.name t
git add -A
git commit -qm "base"
BASE_SHA="$(git rev-parse HEAD)"
echo "changed" >"$repo/oauth-user-inspector/app/index.ts"
git add -A
git commit -qm "feat(oauth): a change that must deploy"
HEAD_SHA="$(git rev-parse HEAD)"

# Unit metadata, exactly the shape delivery() emits.
cat >"$repo/bazel-bin/oauth-user-inspector/infra/app/oauth-user-inspector.delivery.json" <<EOF
{"schema":1,"name":"oauth-user-inspector","kind":"cloud-run",
 "environments":["development","nonproduction","production"],
 "extra_paths":["oauth-user-inspector/"],"exclude_paths":[],"graph_targets":[]}
EOF

# --- stubs --------------------------------------------------------------------
stubs="$work/stubs"
mkdir -p "$stubs"
cat >"$stubs/bazel" <<EOF
#!/usr/bin/env bash
case "\$1" in
  query) echo "//oauth-user-inspector/infra/app:oauth-user-inspector.delivery_unit" ;;
  build) exit 0 ;;
  info)  echo "$repo/bazel-bin" ;;
esac
EOF
# gh stub: \$STUB_INFLIGHT controls the in-flight count; \$STUB_DELIVERED_SHA is
# the head sha of the run whose job succeeded (empty => no successful delivery).
cat >"$stubs/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "run" ] && [ "$2" = "list" ]; then
  case "$*" in
    *"length"*) echo "${STUB_INFLIGHT:-0}"; exit 0 ;;
    *) [ -n "${STUB_DELIVERED_SHA:-}" ] && echo "111 ${STUB_DELIVERED_SHA}"; exit 0 ;;
  esac
fi
if [ "$1" = "api" ]; then
  # jobs listing: report the unit's dev job as successful for run 111
  case "$*" in
    *"/runs/111/jobs"*) [ -n "${STUB_DELIVERED_SHA:-}" ] && echo "oauth-user-inspector-development / deploy"; exit 0 ;;
  esac
  exit 0
fi
exit 0
EOF
chmod +x "$stubs/bazel" "$stubs/gh"

run_drift() { # <inflight> <delivered_sha> ; echoes "<rc> <stdout>"
    local out rc
    out="$(cd "$repo" && env PATH="$stubs:/usr/bin:/bin" \
        STUB_INFLIGHT="$1" STUB_DELIVERED_SHA="$2" \
        REPO="o/r" bash "$SCRIPT" 2>"$work/err")"
    rc=$?
    echo "$rc ${out}"
}

echo "--- drift is detected when a unit is behind main ---"
read -r rc out <<<"$(run_drift 0 "$BASE_SHA")"
if [ "$rc" -eq 1 ] && [ "$out" = "DRIFT" ]; then
    pass "a unit whose last delivery predates an affecting commit reports DRIFT"
else
    fail "expected rc=1/DRIFT, got rc=$rc out='$out'"
    sed 's/^/      /' "$work/err" >&2
fi
if grep -q 'DRIFT oauth-user-inspector' "$work/err"; then
    pass "the drift line names the unit and its last-delivered commit"
else
    fail "drift report does not name the unit"
fi

echo "--- no drift when the unit already has main ---"
read -r rc out <<<"$(run_drift 0 "$HEAD_SHA")"
if [ "$rc" -eq 0 ] && [ "$out" = "OK" ]; then
    pass "a unit delivered at main HEAD reports OK"
else
    fail "expected rc=0/OK, got rc=$rc out='$out'"
    sed 's/^/      /' "$work/err" >&2
fi

echo "--- an in-flight run suppresses the report ---"
read -r rc out <<<"$(run_drift 2 "$BASE_SHA")"
if [ "$rc" -eq 0 ] && [ "$out" = "IN_FLIGHT" ]; then
    pass "mid-convergence is not reported as drift (rc=$rc)"
else
    fail "expected rc=0/IN_FLIGHT, got rc=$rc out='$out'"
fi

echo "--- an unknown delivery state is NOT treated as healthy ---"
read -r rc out <<<"$(run_drift 0 "")"
if [ "$rc" -eq 1 ]; then
    pass "no successful delivery found => reported, not silently OK (rc=$rc)"
else
    fail "expected rc=1 for unknown state, got rc=$rc out='$out'"
fi

echo
if [ "$fail_n" -gt 0 ]; then
    echo "FAILED: $fail_n"
    exit 1
fi
echo "ALL PASS ($pass_n)"
