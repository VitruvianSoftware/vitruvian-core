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

# Hermetic test for tools/ci/site-pr-automerge.sh. A fake `gh` answers from
# env fixtures and logs every call; no network, no credentials, no jq (the
# RBE image has none). The fake never evaluates --jq, so it answers with what
# the real filter prints: "<armed> <draft> <head> <hold labels>".
#
# Usage: site-pr-automerge_test.sh [path/to/site-pr-automerge.sh]

set -uo pipefail

SCRIPT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/site-pr-automerge.sh}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"

fails=0
ok() { printf '  ok - %s\n' "$1"; }
bad() {
  printf '  NOT OK - %s\n' "$1" >&2
  fails=$((fails + 1))
  sed 's/^/    log: /' "$work/log" >&2
  sed 's/^/    out: /' "$work/stdout" >&2
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_GH_LOG"
case "$1 $2" in
  "pr list")
    [ "${FAKE_LIST_RC:-0}" = "0" ] || { echo "gh: HTTP 502" >&2; exit 1; }
    printf '%s\n' "${FAKE_LIST_OUT-42}"
    ;;
  "pr view")
    [ "${FAKE_VIEW_RC:-0}" = "0" ] || { echo "gh: HTTP 500" >&2; exit 1; }
    case "$*" in
      *headRefOid*) printf '%s\n' "${FAKE_STATE:-false false sha1 }" ;;
      *) printf '%s\n' "${FAKE_ARMED:-false}" ;;
    esac
    ;;
  "pr merge")
    case "$*" in
      *--disable-auto*) [ "${FAKE_DISABLE_RC:-0}" = "0" ] || { echo "gh: HTTP 422" >&2; exit 1; } ;;
      *) [ "${FAKE_MERGE_RC:-0}" = "0" ] || { echo "gh: HTTP 422" >&2; exit 1; } ;;
    esac
    ;;
  *)
    echo "unexpected gh call: $*" >&2
    exit 99
    ;;
esac
EOF
chmod +x "$work/bin/gh"

run() { # <mode args...> -- <env...>
  local args=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    args+=("$1")
    shift
  done
  [ "$#" -gt 0 ] && shift
  : >"$work/log"
  : >"$work/summary"
  if [[ "$SCRIPT" == *.sh ]]; then
    env PATH="$work/bin:$PATH" GH_TOKEN=x REPO=o/r FAKE_GH_LOG="$work/log" \
      GITHUB_STEP_SUMMARY="$work/summary" "$@" \
      bash "$SCRIPT" "${args[@]}" >"$work/stdout" 2>&1
  else
    env PATH="$work/bin:$PATH" GH_TOKEN=x REPO=o/r FAKE_GH_LOG="$work/log" \
      GITHUB_STEP_SUMMARY="$work/summary" "$@" \
      "$SCRIPT" "${args[@]}" >"$work/stdout" 2>&1
  fi
  echo $?
}

armed_at() { grep -qx "pr merge 42 --repo o/r --squash --auto --match-head-commit $1" "$work/log"; }
any_arm() { grep -q -- '--auto' "$work/log"; }
disabled() { grep -qx 'pr merge 42 --repo o/r --disable-auto' "$work/log"; }
labels_touched() { grep -q -e '^pr edit' -e '-label' -e '^label' "$work/log"; }

echo "--- arm ---"
rc="$(run arm --branch auto/x --sha sha1 --)"
if [ "$rc" = 0 ] && armed_at sha1 && grep -q 'Armed auto-merge on #42' "$work/summary"; then
  ok "a new pull request is armed, squash, at the commit this run pushed"
else bad "a new pull request was not armed at sha1 (rc=$rc)"; fi

rc="$(run arm --branch auto/x --sha sha1 -- FAKE_STATE='true false sha1 ')"
if [ "$rc" = 0 ] && ! any_arm && ! disabled && grep -q 'already on' "$work/summary"; then
  ok "already armed at this head: left alone (idempotent)"
else bad "an armed pull request was touched again (rc=$rc)"; fi

rc="$(run arm --branch auto/x --sha sha1 -- FAKE_STATE='false false sha1 do-not-automerge')"
if [ "$rc" = 0 ] && ! any_arm && ! disabled && ! labels_touched \
  && grep -q 'not armed: it is held (do-not-automerge)' "$work/summary"; then
  ok "do-not-automerge: not armed, the label left on, the summary says why"
else bad "a do-not-automerge hold was not respected (rc=$rc)"; fi

rc="$(run arm --branch auto/x --sha sha1 -- FAKE_STATE='true false sha1 needs-human')"
if [ "$rc" = 0 ] && disabled && ! any_arm && ! labels_touched; then
  ok "needs-human with auto-merge on: turned off, not re-armed, label left on"
else bad "a needs-human hold on an armed pull request was not enforced (rc=$rc)"; fi

rc="$(run arm --branch auto/x --sha sha1 -- FAKE_STATE='false true sha1 ')"
if [ "$rc" = 0 ] && ! any_arm && grep -q 'a draft' "$work/summary"; then
  ok "a draft is not armed"
else bad "a draft was armed (rc=$rc)"; fi

rc="$(run arm --branch auto/x --sha sha1 -- FAKE_STATE='true false sha2 ')"
if [ "$rc" = 0 ] && disabled && ! any_arm && grep -q '::warning title=auto-merge not armed::' "$work/stdout"; then
  ok "head moved past this run's commit: auto-merge off, not re-armed, a warning"
else bad "a commit this run did not push could ride an arming (rc=$rc)"; fi

echo "--- arm: failures are loud ---"
rc="$(run arm --branch auto/x --sha sha1 -- FAKE_MERGE_RC=1)"
if [ "$rc" = 1 ] && grep -q '::error title=auto-merge not armed::' "$work/stdout" \
  && grep -q 'WARNING' "$work/summary" && grep -q 'Auto-merge is not armed' "$work/summary"; then
  ok "a refused arm fails the step with an error and a summary warning"
else bad "a refused arm passed quietly (rc=$rc)"; fi

rc="$(run arm --branch auto/x --sha sha1 -- FAKE_LIST_RC=1)"
if [ "$rc" = 1 ] && ! grep -q '^pr merge' "$work/log" && grep -q 'Auto-merge is not armed' "$work/summary"; then
  ok "a failed lookup is not read as 'no pull request'"
else bad "a failed lookup passed (rc=$rc)"; fi

rc="$(run arm --branch auto/x --sha sha1 -- FAKE_LIST_OUT=)"
if [ "$rc" = 1 ] && grep -q 'no open pull request' "$work/summary"; then
  ok "no open pull request right after the push fails"
else bad "a missing pull request passed (rc=$rc)"; fi

rc="$(run arm --branch auto/x --sha sha1 -- FAKE_VIEW_RC=1)"
if [ "$rc" = 1 ] && ! grep -q '^pr merge' "$work/log"; then
  ok "an unreadable pull request fails without arming"
else bad "an unreadable pull request was armed or passed (rc=$rc)"; fi

rc="$(run arm --branch auto/x --sha sha1 -- FAKE_STATE='true false sha1 do-not-automerge' FAKE_DISABLE_RC=1)"
if [ "$rc" = 1 ] && ! any_arm; then
  ok "a hold whose auto-merge cannot be turned off fails the step"
else bad "a hold left armed passed (rc=$rc)"; fi

echo "--- disarm (before the push) ---"
rc="$(run disarm --branch auto/x -- FAKE_ARMED=true)"
if [ "$rc" = 0 ] && disabled && ! any_arm; then
  ok "an armed pull request is turned off before the push"
else bad "an armed pull request was not turned off (rc=$rc)"; fi

rc="$(run disarm --branch auto/x -- FAKE_ARMED=false)"
if [ "$rc" = 0 ] && ! grep -q '^pr merge' "$work/log"; then
  ok "auto-merge already off: nothing to do"
else bad "disarm acted on an unarmed pull request (rc=$rc)"; fi

rc="$(run disarm --branch auto/x -- FAKE_LIST_OUT=)"
if [ "$rc" = 0 ] && ! grep -q '^pr view' "$work/log"; then
  ok "no pull request yet: nothing to do"
else bad "disarm without a pull request misbehaved (rc=$rc)"; fi

rc="$(run disarm --branch auto/x -- FAKE_LIST_RC=1)"
if [ "$rc" = 1 ]; then
  ok "a failed lookup before the push fails the step"
else bad "a failed lookup before the push passed (rc=$rc)"; fi

rc="$(run disarm --branch auto/x -- FAKE_ARMED=true FAKE_DISABLE_RC=1)"
if [ "$rc" = 1 ]; then
  ok "auto-merge that cannot be turned off before the push fails the step"
else bad "a failed disarm passed (rc=$rc)"; fi

echo "--- usage ---"
rc="$(run arm --branch auto/x --)"
if [ "$rc" = 2 ] && [ ! -s "$work/log" ]; then
  ok "arm without --sha is refused before any gh call"
else bad "arm without --sha ran (rc=$rc)"; fi

rc="$(run arm --branch auto/x --sha sha1 -- REPO=)"
if [ "$rc" = 2 ] && [ ! -s "$work/log" ]; then
  ok "no REPO is refused before any gh call"
else bad "ran without REPO (rc=$rc)"; fi

if [ "$fails" -gt 0 ]; then
  echo "$fails failed" >&2
  exit 1
fi
echo "all passed"
