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

# Hermetic guard for tools/ci/release-hold.sh. Fake `gh` (no network, no
# credentials — mirrors resolve-deploy-base_test.sh's fake-gh pattern) that
# dispatches on the gh subcommand and logs every invocation for assertion.
#
# Specifically pins the bug fix: a failed `gh pr list` (the open-release-PR
# lookup) must be surfaced as an indeterminate ::warning:: and leave things
# untouched, exactly like the already-correct `gh run view` failure handling
# — NOT silently treated as "no open release PR" (the pre-fix behavior).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/release-hold.sh"

fails=0
ok() { printf '  ok - %s\n' "$1"; }
bad() { printf '  NOT OK - %s\n' "$1" >&2; fails=$((fails + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# fake gh: dispatches on "$1 $2" (e.g. "pr list", "run view"), logs the full
# invocation, and answers from env-controlled canned fixtures.
cat > "$work/fake-gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_GH_LOG}"
case "$1 $2" in
  "pr list")
    if [ "${FAKE_PR_LIST_RC:-0}" != "0" ]; then
      echo "gh: HTTP 502 (something went wrong)" >&2
      exit "${FAKE_PR_LIST_RC}"
    fi
    printf '%s' "${FAKE_PR_LIST_OUT:-}"
    ;;
  "run view")
    if [ "${FAKE_RUN_VIEW_RC:-0}" != "0" ]; then
      echo "gh: HTTP 500 (internal error)" >&2
      exit "${FAKE_RUN_VIEW_RC}"
    fi
    printf '%s' "${FAKE_RUN_VIEW_OUT:-}"
    ;;
  "pr view")
    printf '%s' "${FAKE_PR_VIEW_LABELS_OUT:-}"
    ;;
  "pr edit" | "pr merge" | "pr comment")
    exit 0
    ;;
  *)
    echo "unexpected fake gh invocation: $*" >&2
    exit 99
    ;;
esac
EOF
chmod +x "$work/fake-gh"

# The script hardcodes `gh` as the binary (no GH_BIN override, matching the
# original inline step which always called gh directly) — so point PATH at a
# directory containing an executable literally named `gh`.
mkdir -p "$work/bin"
ln -sf "$work/fake-gh" "$work/bin/gh"

run() { # <env...>
  : > "$work/log"
  env PATH="$work/bin:$PATH" GH_TOKEN=x FAKE_GH_LOG="$work/log" \
    REPO="owner/repo" RUN_ID="999" DEV_JOB="deploy-dev / deploy" COMPONENT="tabula-api" \
    "$@" bash "$SCRIPT" >"$work/stdout" 2>"$work/stderr"
  echo $?
}

echo "--- bug fix: gh pr list failure must NOT look like 'no open PR' ---"
rc="$(run FAKE_PR_LIST_RC=1)"
if [ "$rc" = "0" ] && grep -q "::warning title=release-hold indeterminate::" "$work/stdout" \
   && grep -q "could not list open release PRs" "$work/stdout"; then
  ok "gh pr list failure surfaces a titled indeterminate warning (exit 0, informational)"
else
  bad "gh pr list failure not handled correctly (rc=$rc)"; sed 's/^/    /' "$work/stdout" "$work/stderr" >&2
fi
if [ "$(grep -c '^pr list' "$work/log")" = "1" ] && ! grep -q '^run view' "$work/log"; then
  ok "gh pr list failure short-circuits before ever calling 'gh run view'"
else
  bad "expected exactly one 'pr list' call and no 'run view' call, got:"; sed 's/^/    /' "$work/log" >&2
fi

echo "--- happy paths ---"
rc="$(run FAKE_PR_LIST_OUT=42 FAKE_RUN_VIEW_RC=1)"
if [ "$rc" = "0" ] && grep -q "::warning title=release-hold indeterminate::could not read jobs" "$work/stdout"; then
  ok "gh run view failure (the ALREADY-correct path) still surfaces its own indeterminate warning"
else
  bad "gh run view failure regressed (rc=$rc)"; sed 's/^/    /' "$work/stdout" >&2
fi

rc="$(run FAKE_PR_LIST_OUT="")"
if [ "$rc" = "0" ] && grep -q "No open release PR" "$work/stdout"; then
  ok "genuinely empty PR list (real 'nothing open') still exits cleanly"
else
  bad "empty PR list case regressed (rc=$rc)"; sed 's/^/    /' "$work/stdout" >&2
fi

jobs_success=$'deploy-dev / deploy\tsuccess'
rc="$(run FAKE_PR_LIST_OUT=42 FAKE_RUN_VIEW_OUT="$jobs_success" FAKE_PR_VIEW_LABELS_OUT="do-not-automerge")"
if [ "$rc" = "0" ] && grep -q "^pr edit 42 --repo owner/repo --remove-label do-not-automerge$" "$work/log" \
   && grep -q "^pr merge 42 --repo owner/repo --squash --auto$" "$work/log"; then
  ok "conclusion=success with an existing hold clears the label and re-enables auto-merge"
else
  bad "success-with-hold path wrong, log:"; sed 's/^/    /' "$work/log" >&2
fi

rc="$(run FAKE_PR_LIST_OUT=42 FAKE_RUN_VIEW_OUT="$jobs_success" FAKE_PR_VIEW_LABELS_OUT="")"
if [ "$rc" = "0" ] && ! grep -q "^pr edit" "$work/log" && ! grep -q "^pr merge" "$work/log"; then
  ok "conclusion=success with no hold in place makes no mutating calls"
else
  bad "success-without-hold path made unexpected calls:"; sed 's/^/    /' "$work/log" >&2
fi

jobs_failure=$'deploy-dev / deploy\tfailure'
rc="$(run FAKE_PR_LIST_OUT=42 FAKE_RUN_VIEW_OUT="$jobs_failure")"
if [ "$rc" = "0" ] && grep -q "^pr edit 42 --repo owner/repo --add-label do-not-automerge$" "$work/log" \
   && grep -q "^pr merge 42 --repo owner/repo --disable-auto$" "$work/log" \
   && grep -q "^pr comment 42 --repo owner/repo --body" "$work/log"; then
  ok "conclusion=failure adds the hold label, disables auto-merge, and comments"
else
  bad "failure path wrong, log:"; sed 's/^/    /' "$work/log" >&2
fi

jobs_other=$'some-other-job\tsuccess'
rc="$(run FAKE_PR_LIST_OUT=42 FAKE_RUN_VIEW_OUT="$jobs_other")"
if [ "$rc" = "0" ] && grep -q "has no 'deploy-dev / deploy' job" "$work/stdout" \
   && ! grep -q "^pr edit" "$work/log" && ! grep -q "^pr merge" "$work/log"; then
  ok "DEV_JOB absent from the run's jobs makes no mutating calls"
else
  bad "missing-job path wrong:"; sed 's/^/    /' "$work/stdout" "$work/log" >&2
fi

echo "--- matrix source filtering ---"
rc="$(run SOURCE=tabula-deploy TRIGGERED_BY=oauth-user-inspector-deploy)"
if [ "$rc" = "0" ] && [ ! -s "$work/log" ] && grep -q "this entry is for 'tabula-deploy'" "$work/stdout"; then
  ok "SOURCE != TRIGGERED_BY skips entirely with zero gh calls"
else
  bad "source-filter path wrong (rc=$rc), log:"; sed 's/^/    /' "$work/log" "$work/stdout" >&2
fi

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails" >&2; exit 1; fi
echo "ALL PASS"
