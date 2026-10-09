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

# Hermetic guard for tools/ci/release-pr-dequeue.sh. A fake `gh` (no network,
# no credentials — the release-beta-gate_test.sh pattern) answers each lookup
# from fixture files and logs every invocation for assertion. A fixture holds
# what the real call's --jq would print; a missing one prints nothing, and a
# `<name>.rc` file makes that call fail.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/release-pr-dequeue.sh"

fails=0
ok() { printf '  ok - %s\n' "$1"; }
bad() { printf '  NOT OK - %s\n' "$1" >&2; fails=$((fails + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
FX="$work/fx"

cat > "$work/fake-gh" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_GH_LOG}"
answer() { # <fixture name>
  if [ -f "${FX}/$1.rc" ]; then echo "gh: HTTP 502" >&2; exit 1; fi
  [ -f "${FX}/$1" ] && cat "${FX}/$1"
  exit 0
}
case "$1 $2" in
  "api graphql")
    case "$*" in
      *dequeuePullRequest*) answer dequeue ;;
      *pullRequests*) answer prs ;;
      *) echo "unexpected fake gh graphql call: $*" >&2; exit 99 ;;
    esac
    ;;
  api\ *)
    path="$2"
    case "$path" in
      */commits/*) answer parent ;;
      */commits\?sha=*)
        sha="${path#*commits?sha=}"
        answer "code.${sha%%&*}"
        ;;
      *) echo "unexpected fake gh api path: $path" >&2; exit 99 ;;
    esac
    ;;
  *) echo "unexpected fake gh invocation: $*" >&2; exit 99 ;;
esac
FAKE
chmod +x "$work/fake-gh"
mkdir -p "$work/bin"
ln -sf "$work/fake-gh" "$work/bin/gh"

fx() { printf '%s' "$2" > "$FX/$1"; } # <name> <content>
fresh() { # a QUEUED release PR built on main8 (app code app5); main is now main9
  rm -rf "$FX"; mkdir -p "$FX"
  fx prs $'42\tPR_node42\thead1\ttrue'
  fx parent main8
  fx code.main8 app5
  fx code.main9 app6
}

run() {
  : > "$work/log"
  env PATH="$work/bin:$PATH" GH_TOKEN=x FAKE_GH_LOG="$work/log" FX="$FX" \
    REPO="owner/repo" COMPONENT="vitruvian" CODE_PATH="apps/desktop/vitruvian" \
    MAIN_SHA="main9" bash "$SCRIPT" >"$work/stdout" 2>"$work/stderr"
  echo $?
}
show() { sed 's/^/    /' "$work/stdout" "$work/stderr" "$work/log" >&2; }
dequeued() { grep -q '^api graphql -f id=PR_node42 .*dequeuePullRequest' "$work/log"; }
warned() { grep -q '^::warning title=release PR left in the queue::' "$work/stdout"; }

echo "--- when it dequeues ---"
fresh
rc="$(run)"
if [ "$rc" = "0" ] && dequeued \
   && grep -q -- '-f branch=release-please--branches--main--components--vitruvian ' "$work/log" \
   && grep -q '^api repos/owner/repo/commits/head1 ' "$work/log" \
   && grep -q '^api repos/owner/repo/commits?sha=main8&path=apps/desktop/vitruvian&per_page=1 ' "$work/log" \
   && grep -q '^api repos/owner/repo/commits?sha=main9&path=apps/desktop/vitruvian&per_page=1 ' "$work/log"; then
  ok "a queued release PR that does not list main's newest app change is dequeued"
else
  bad "stale queued release PR not dequeued (rc=$rc)"; show
fi

echo "--- when it leaves the PR alone ---"
fresh; fx code.main9 app5
rc="$(run)"
if [ "$rc" = "0" ] && ! dequeued && ! warned; then
  ok "a queued release PR that already lists main's newest app change stays queued"
else
  bad "up-to-date queued release PR was touched (rc=$rc)"; show
fi

fresh; fx prs $'42\tPR_node42\thead1\tfalse'
rc="$(run)"
if [ "$rc" = "0" ] && ! dequeued && ! grep -q '^api repos/' "$work/log"; then
  ok "a release PR that is not queued needs nothing (and no further lookups)"
else
  bad "unqueued release PR was touched (rc=$rc)"; show
fi

fresh; fx prs ''
rc="$(run)"
if [ "$rc" = "0" ] && ! dequeued && grep -q 'nothing to dequeue' "$work/stdout"; then
  ok "no open release PR is a clean no-op"
else
  bad "no-PR case wrong (rc=$rc)"; show
fi

echo "--- a failed lookup never dequeues and never fails the release run ---"
for broken in prs parent code.main8 code.main9; do
  fresh; : > "$FX/$broken.rc"
  rc="$(run)"
  if [ "$rc" = "0" ] && ! dequeued && warned; then
    ok "failed lookup '${broken}' warns and leaves the PR queued"
  else
    bad "failed lookup '${broken}' mishandled (rc=$rc)"; show
  fi
done

for empty in parent code.main8 code.main9; do
  fresh; fx "$empty" ''
  rc="$(run)"
  if [ "$rc" = "0" ] && ! dequeued && warned; then
    ok "empty answer for '${empty}' warns and leaves the PR queued"
  else
    bad "empty answer for '${empty}' mishandled (rc=$rc)"; show
  fi
done

fresh; : > "$FX/dequeue.rc"
rc="$(run)"
if [ "$rc" = "0" ] && dequeued && warned && ! grep -q 'is out of the merge queue' "$work/stdout"; then
  ok "a refused dequeue warns, does not claim success, and lets release-please report the failure"
else
  bad "refused dequeue mishandled (rc=$rc)"; show
fi

echo "--- the release workflow runs it before release-please ---"
WF="${HERE}/../../.github/workflows/vitruvian-release.yaml"
at_dequeue="$(grep -n 'run: bash tools/ci/release-pr-dequeue.sh' "$WF" | head -1 | cut -d: -f1)"
at_release="$(grep -n 'uses: googleapis/release-please-action@' "$WF" | head -1 | cut -d: -f1)"
if [ -n "$at_dequeue" ] && [ -n "$at_release" ] && [ "$at_dequeue" -lt "$at_release" ]; then
  ok "vitruvian-release.yaml dequeues before release-please updates the branch"
else
  bad "vitruvian-release.yaml does not run release-pr-dequeue.sh before release-please (dequeue line '${at_dequeue}', release-please line '${at_release}')"
fi

if [ "$fails" -ne 0 ]; then
  echo "FAILED: $fails check(s)" >&2
  exit 1
fi
echo "PASS"
