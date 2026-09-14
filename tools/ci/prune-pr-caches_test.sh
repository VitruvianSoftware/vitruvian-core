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
  # Merge-queue refs. 106's branch is gone (deletable), 107's is still in the
  # queue (must survive), 108's existence cannot be determined (must survive).
  printf '106\t6291456\trefs/heads/gh-readonly-queue/main/pr-903-deadbeef\n'
  printf '107\t7340032\trefs/heads/gh-readonly-queue/main/pr-904-cafebabe\n'
  printf '108\t8388608\trefs/heads/gh-readonly-queue/main/pr-905-f00dface\n'
  exit 0
fi
# Branch existence, driven by $STUB_BRANCHES ("pr-903:gone,pr-904:live,...").
# "gone" answers like the real API's 404; "err" is a transport failure, which
# must NOT be read as deletion.
if [ "$1" = "api" ] && [ "${2:-}" != "--paginate" ] && [ "${2:-}" != "-X" ]; then
  for pair in ${STUB_BRANCHES//,/ }; do
    key="${pair%%:*}"
    case "$2" in *"$key"*)
      case "${pair#*:}" in
        gone) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
        live) echo '{"name":"x"}'; exit 0 ;;
        err)  echo "error connecting to api.github.com" >&2; exit 1 ;;
      esac ;;
    esac
  done
  echo '{"name":"x"}'; exit 0   # unknown branch -> looks alive -> must be kept
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
        STUB_STATES="$1" STUB_BRANCHES="${STUB_BRANCHES:-}" DELETED="$work/deleted" \
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

echo "--- the remaining-budget accounting is correct ---"
# Fixture: 8 entries totalling 1+2+3+5+4 + 6+7+8 MiB = 36 MiB (the last three
# are the merge-queue rows, all kept here because no STUB_BRANCHES is set so
# every branch looks alive). Deleting 101 (1 MiB) and 104 (4 MiB) must leave
# 6 entries / 31 MiB. This lived as an inline `run:`
# block in the workflow and shipped broken -- `gh api --paginate` with a --jq
# AGGREGATE emits one result PER PAGE, so the total was two numbers and the
# arithmetic died. Inline workflow steps have no tests; this does.
run "900:MERGED,901:OPEN,902:CLOSED"
if echo "$OUT" | grep -q 'remaining_entries=6'; then
    pass "remaining_entries counts every ref, not just the deleted ones"
else
    fail "expected remaining_entries=6, got '$OUT'"
fi
if echo "$OUT" | grep -q 'remaining_mib=31'; then
    pass "remaining_mib subtracts exactly what was freed (36 - 5)"
else
    fail "expected remaining_mib=31, got '$OUT'"
fi
if echo "$OUT" | grep -q 'freed_mib=5'; then
    pass "freed_mib reports the reclaimed total"
else
    fail "expected freed_mib=5, got '$OUT'"
fi
# The workflow appends this stdout directly to $GITHUB_OUTPUT, which GitHub
# parses LINE BY LINE. Space-separated pairs on one line would define a single
# output whose value swallows the rest.
if [ "$(echo "$OUT" | grep -c '^[a-z_]*=[0-9]*$')" -eq 4 ]; then
    pass "emits exactly 4 key=value lines, one per line (GITHUB_OUTPUT shape)"
else
    fail "output is not GITHUB_OUTPUT-shaped: '$OUT'"
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

echo "--- merge-queue refs: only a CONFIRMED-deleted branch is swept ---"
# 106's branch is gone (the orphan this section exists for), 107 is still in the
# queue, 108's existence check failed at the transport layer. Only 106 may go.
STUB_BRANCHES="pr-903:gone,pr-904:live,pr-905:err" run "900:MERGED,901:MERGED,902:MERGED"
case "$DELETED_IDS" in *106*) pass "a queue cache whose branch 404s is deleted" ;; *) fail "did NOT delete orphaned queue cache 106 (got '$DELETED_IDS')" ;; esac
case "$DELETED_IDS" in *107*) fail "DELETED cache 107 — its queue branch is still LIVE, that entry is mid-merge" ;; *) pass "a live queue entry keeps its cache" ;; esac
# The one that matters most: a transport failure exits non-zero exactly like a
# 404. If the script ever tests `if ! gh api ...` instead of matching the 404,
# a rate limit silently starts deleting live queue caches and only this fails.
case "$DELETED_IDS" in *108*) fail "DELETED cache 108 — a transport error was treated as proof the branch was deleted" ;; *) pass "an undeterminable branch is left alone, not guessed" ;; esac

echo "--- an unrecognised branch is assumed alive ---"
STUB_BRANCHES="" run "900:MERGED,901:MERGED,902:MERGED"
case "$DELETED_IDS" in
    *106* | *107* | *108*) fail "deleted a queue cache with no positive proof its branch was gone (got '$DELETED_IDS')" ;;
    *) pass "no 404, no deletion" ;;
esac

echo "--- the on-close hook sweeps that PR's queue branches too ---"
STUB_BRANCHES="pr-903:gone,pr-904:live,pr-905:err" run "903:MERGED" 903
if [ "$DELETED_IDS" = "106 " ]; then
    pass "prune-pr-caches.sh 903 swept only PR 903's queue cache"
else
    fail "expected only '106 ', got '$DELETED_IDS'"
    sed 's/^/      /' "$work/err" >&2
fi

echo
if [ "$fail_n" -gt 0 ]; then
    echo "FAILED: $fail_n"
    exit 1
fi
echo "ALL PASS ($pass_n)"
