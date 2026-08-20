#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Tests for prune-pr-caches.sh. The property that matters is NEGATIVE: this
# script deletes things, so the tests exist mainly to prove what it will NOT
# touch -- an open PR's cache, a non-PR (main) cache, or a PR whose state it
# could not determine. Deleting a live PR's cache costs that PR a cold rebuild;
# deleting main's costs every lane.
set -uo pipefail

SCRIPT="${1:?usage: prune-pr-caches_test.sh <path to prune-pr-caches.sh>}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"

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

stubs="$work/stubs"
mkdir -p "$stubs"
# gh stub. Cache listing is fixed; PR states come from $STUB_STATES ("num:STATE,..").
# Every DELETE is appended to $DELETED so the tests can assert on exactly which
# ids were removed.
cat >"$stubs/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "api" ] && [ "${2:-}" = "--paginate" ]; then
  printf '101\t1048576\trefs/pull/900/merge\n'
  printf '102\t2097152\trefs/pull/901/merge\n'
  printf '103\t3145728\trefs/heads/main\n'
  # A branch whose 3rd path segment ("900") is also a MERGED PR number. Only the
  # refs/pull/* filter can protect this; the unknown-state guard cannot, because
  # the state DOES resolve. Without this row, dropping the filter is invisible.
  printf '105\t5242880\trefs/heads/900\n'
  printf '104\t4194304\trefs/pull/902/merge\n'
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  n="$3"
  for pair in ${STUB_STATES//,/ }; do
    case "$pair" in "$n":*) echo "${pair#*:}"; exit 0 ;; esac
  done
  exit 1   # unknown PR -> gh fails, script must not guess
fi
if [ "$1" = "api" ] && [ "$2" = "-X" ] && [ "$3" = "DELETE" ]; then
  echo "$4" | sed 's|.*/||' >> "$DELETED"
  exit 0
fi
exit 0
EOF
chmod +x "$stubs/gh"

run() { # <states> [pr] ; sets DELETED_IDS
    : >"$work/deleted"
    OUT="$(env PATH="$stubs:/usr/bin:/bin" REPO="o/r" \
        STUB_STATES="$1" DELETED="$work/deleted" \
        bash "$SCRIPT" ${2:-} 2>"$work/err")"
    DELETED_IDS="$(sort "$work/deleted" | tr '\n' ' ')"
}

echo "--- deletes only closed/merged PR caches ---"
run "900:MERGED,901:OPEN,902:CLOSED"
if [ "$DELETED_IDS" = "101 104 " ]; then
    pass "merged (101) and closed (104) deleted; open PR's cache untouched"
else
    fail "expected '101 104 ', got '$DELETED_IDS'"
    sed 's/^/      /' "$work/err" >&2
fi
case "$DELETED_IDS" in *103*) fail "DELETED a refs/heads/main cache — never acceptable" ;; *) pass "main's cache is never a candidate" ;; esac
# 105 lives on refs/heads/900 and "900" IS a merged PR. Only the refs/pull/*
# filter stands between it and deletion, so this is the one assertion that
# actually pins that filter rather than the state guard behind it.
case "$DELETED_IDS" in *105*) fail "DELETED a branch cache whose name collides with a merged PR number — the refs/pull filter is gone" ;; *) pass "a branch ref is excluded by path, not merely by PR-state lookup" ;; esac
case "$DELETED_IDS" in *102*) fail "DELETED an OPEN PR's cache" ;; *) pass "an open PR keeps its cache" ;; esac

echo "--- an undeterminable PR state is left alone, not guessed ---"
run "900:MERGED"   # 901 and 902 unknown: gh pr view fails
if [ "$DELETED_IDS" = "101 " ]; then
    pass "only the confirmed-merged cache was deleted (unknown states skipped)"
else
    fail "expected only '101 ', got '$DELETED_IDS'"
    sed 's/^/      /' "$work/err" >&2
fi

echo "--- single-PR mode touches only that PR ---"
run "900:MERGED,901:MERGED,902:MERGED" 902
if [ "$DELETED_IDS" = "104 " ]; then
    pass "on-close hook for PR 902 deleted only its own cache"
else
    fail "expected '104 ', got '$DELETED_IDS'"
fi

echo "--- DRY_RUN deletes nothing ---"
: >"$work/deleted"
env PATH="$stubs:/usr/bin:/bin" REPO="o/r" STUB_STATES="900:MERGED,901:MERGED,902:MERGED" \
    DELETED="$work/deleted" DRY_RUN=1 bash "$SCRIPT" >/dev/null 2>&1
if [ ! -s "$work/deleted" ]; then
    pass "DRY_RUN issued no DELETE calls"
else
    fail "DRY_RUN deleted: $(tr '\n' ' ' <"$work/deleted")"
fi

echo
if [ "$fail_n" -gt 0 ]; then
    echo "FAILED: $fail_n"
    exit 1
fi
echo "ALL PASS ($pass_n)"
