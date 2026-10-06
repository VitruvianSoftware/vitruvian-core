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

# Hermetic guard for tools/ci/release-beta-gate.sh. A fake `gh` (no network,
# no credentials — the release-hold_test.sh pattern) answers each lookup from
# fixture files and logs every invocation for assertion. A fixture holds what
# the real call's --jq would print; a missing one prints nothing, and a
# `<name>.rc` file makes that call fail.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/release-beta-gate.sh"

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
  "pr list") answer prs ;;
  "pr view") answer comments ;;
  "pr edit" | "pr merge" | "pr comment") exit 0 ;;
  api\ *)
    path="$2"
    case "$path" in
      */commits/*) answer parent ;;
      */commits\?sha=*)
        sha="${path#*commits?sha=}"
        answer "code.${sha%%&*}"
        ;;
      */actions/workflows/*head_sha=*) answer ownruns ;;
      */actions/workflows/*) answer runs ;;
      */actions/runs/*/jobs*)
        id="${path#*actions/runs/}"
        answer "jobs.${id%%/*}"
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
fresh() { # a release PR on main commit main9, whose app code is app5
  rm -rf "$FX"; mkdir -p "$FX"
  fx prs $'42\thead1\tfalse\tfalse\t'
  fx parent main9
  fx code.main9 app5
}

run() {
  : > "$work/log"
  env PATH="$work/bin:$PATH" GH_TOKEN=x FAKE_GH_LOG="$work/log" FX="$FX" \
    REPO="owner/repo" COMPONENT="vitruvian" CODE_PATH="apps/desktop/vitruvian" \
    BETA_JOB="vitruvian-beta" WORKFLOW="delivery.yaml" \
    bash "$SCRIPT" >"$work/stdout" 2>"$work/stderr"
  echo $?
}
show() { sed 's/^/    /' "$work/stdout" "$work/stderr" "$work/log" >&2; }
mutated() { grep -qE '^pr (edit|merge|comment)' "$work/log"; }
enabled() { grep -q '^pr merge 42 --repo owner/repo --squash --auto$' "$work/log"; }
disabled() { grep -q '^pr merge 42 --repo owner/repo --disable-auto$' "$work/log"; }

beta() { printf 'orchestrate\tcompleted\tsuccess\nvitruvian-beta\t%s\t%s' "$1" "$2"; }

echo "--- which run counts ---"
fresh; fx runs $'901\tapp5'; fx jobs.901 "$(beta completed success)"
rc="$(run)"
if [ "$rc" = "0" ] && grep -q '^api repos/owner/repo/commits/head1 ' "$work/log" \
   && grep -q '^api repos/owner/repo/commits?sha=main9&path=apps/desktop/vitruvian&per_page=1 ' "$work/log" \
   && grep -q '^api repos/owner/repo/actions/workflows/delivery.yaml/runs?event=push&branch=main&per_page=20 ' "$work/log" \
   && grep -q '^api repos/owner/repo/actions/runs/901/jobs' "$work/log" && enabled; then
  ok "reads the release commit's parent, the last app commit at it, then that commit's push run"
else
  bad "lookup chain wrong (rc=$rc)"; show
fi

# Newest first: 903 is a newer app change (app7) the PR is not built on, 902
# coalesced app5 (same code), 901 is app5's own run (cancelled), 900 is older.
fresh
fx runs $'903\tmain11\n902\tmain10\n901\tapp5\n900\tapp4'
fx code.main11 app7; fx code.main10 app5
fx jobs.903 "$(beta completed failure)"
fx jobs.902 "$(beta completed success)"
fx jobs.901 "$(beta completed cancelled)"
fx code.main app7
rc="$(run)"
if [ "$rc" = "0" ] && enabled && ! grep -q 'runs/903/jobs' "$work/log" \
   && grep -q 'succeeded for app5 in run 902' "$work/stdout"; then
  ok "a later run that built the same code counts; a newer app change's run does not"
else
  bad "coalesced run not credited (rc=$rc)"; show
fi

fresh
fx runs $'902\tmain10\n901\tapp5\n900\tapp4'
fx code.main10 app5
fx jobs.902 "$(beta completed skipped)"
fx jobs.901 "$(beta completed success)"
fx jobs.900 "$(beta completed failure)"
rc="$(run)"
if [ "$rc" = "0" ] && enabled && ! grep -q 'runs/900/jobs' "$work/log"; then
  ok "a skipped beta defers to an older same-code run"
else
  bad "skip handling wrong (rc=$rc)"; show
fi

fx jobs.901 "$(beta completed cancelled)"
rc="$(run)"
if [ "$rc" = "0" ] && ! enabled && ! grep -qE 'sha=app4|runs/900/' "$work/log"; then
  ok "the search reads nothing older than the code commit's own run"
else
  bad "search went past the code's own run (rc=$rc)"; show
fi

# The code commit's own run has aged out of the window: found by sha.
fresh; fx runs $'905\tmain14\n904\tmain13'; fx code.main14 app5; fx code.main13 app5
fx jobs.904 "$(beta completed skipped)"; fx jobs.905 "$(beta completed skipped)"
fx ownruns 901; fx jobs.901 "$(beta completed failure)"
rc="$(run)"
if [ "$rc" = "0" ] && grep -q '^api repos/owner/repo/actions/workflows/delivery.yaml/runs?head_sha=app5&event=push&per_page=10 ' "$work/log" \
   && grep -q '^pr comment 42' "$work/log" && ! enabled; then
  ok "a code commit older than the window is still judged by its own run"
else
  bad "aged-out run not found by sha (rc=$rc)"; show
fi

fresh; fx runs $'901\tapp5'; fx jobs.901 "$(beta completed cancelled)"; fx ownruns 901
rc="$(run)"
if [ "$rc" = "0" ] && ! grep -q 'head_sha=' "$work/log"; then
  ok "the by-sha lookup is skipped when the window already held the code's own run"
else
  bad "by-sha lookup ran needlessly (rc=$rc)"; show
fi

# main has no app change after app5: newer runs need no lookup of their own.
fresh; fx code.main app5; fx runs $'903\tmain12\n902\tmain10\n901\tapp5'
fx jobs.903 "$(beta completed skipped)"; fx jobs.902 "$(beta completed success)"
rc="$(run)"
if [ "$rc" = "0" ] && enabled && ! grep -qE 'sha=main1[02]&' "$work/log"; then
  ok "with main still on the release's code, newer runs count without a lookup each"
else
  bad "current-code shortcut wrong (rc=$rc)"; show
fi

echo "--- success ---"
fresh; fx prs $'42\thead1\tfalse\ttrue\t'; fx runs $'901\tapp5'; fx jobs.901 "$(beta completed success)"
rc="$(run)"
if [ "$rc" = "0" ] && ! mutated; then
  ok "a green beta with auto-merge already on changes nothing"
else
  bad "success with auto-merge on made calls (rc=$rc)"; show
fi

fresh; fx prs $'42\thead1\tfalse\tfalse\tautorelease: pending,do-not-automerge'
fx runs $'901\tapp5'; fx jobs.901 "$(beta completed success)"
rc="$(run)"
if [ "$rc" = "0" ] && grep -q '^pr edit 42 --repo owner/repo --remove-label do-not-automerge$' "$work/log" && enabled; then
  ok "a green beta clears an earlier hold and enables auto-merge"
else
  bad "success after a hold wrong (rc=$rc)"; show
fi

fresh; fx prs $'42\thead1\ttrue\tfalse\t'; fx runs $'901\tapp5'; fx jobs.901 "$(beta completed success)"
rc="$(run)"
if [ "$rc" = "0" ] && ! mutated; then
  ok "a draft release PR is left for a maintainer"
else
  bad "draft PR was touched (rc=$rc)"; show
fi

echo "--- failure ---"
fresh; fx prs $'42\thead1\tfalse\ttrue\t'; fx runs $'901\tapp5'; fx jobs.901 "$(beta completed failure)"
rc="$(run)"
if [ "$rc" = "0" ] && grep -q '^pr edit 42 --repo owner/repo --add-label do-not-automerge$' "$work/log" \
   && disabled && grep -q '^pr comment 42 --repo owner/repo --body <!-- release-beta-gate:app5 -->' "$work/log" \
   && ! enabled; then
  ok "a red beta holds the PR, disables auto-merge and comments with the commit's marker"
else
  bad "failure path wrong (rc=$rc)"; show
fi

fx comments $'<!-- release-beta-gate:app5 -->\nHeld out of auto-merge'
rc="$(run)"
if [ "$rc" = "0" ] && ! grep -q '^pr comment' "$work/log" && disabled; then
  ok "a red beta already commented on is not commented on again"
else
  bad "duplicate comment (rc=$rc)"; show
fi

fresh; fx runs $'902\tmain10\n901\tapp5'; fx code.main10 app5
fx jobs.902 "$(beta completed success)"; fx jobs.901 "$(beta completed failure)"
rc="$(run)"
if [ "$rc" = "0" ] && enabled && ! grep -q '^pr comment' "$work/log"; then
  ok "the newest decided run wins: a later success outweighs an older failure"
else
  bad "newest-wins wrong (rc=$rc)"; show
fi

echo "--- waiting ---"
for c in "running:$(beta in_progress '')" "queued:$(beta queued '')" "cancelled:$(beta completed cancelled)" \
         "skipped:$(beta completed skipped)" "absent:"$'other-job\tcompleted\tsuccess'; do
  name="${c%%:*}"
  fresh; fx prs $'42\thead1\tfalse\ttrue\t'; fx runs $'901\tapp5'; fx jobs.901 "${c#*:}"
  rc="$(run)"
  if [ "$rc" = "0" ] && disabled && ! enabled && ! grep -q '^pr comment' "$work/log" \
     && grep -q 'waiting' "$work/stdout"; then
    ok "beta ${name}: auto-merge is turned off and the PR waits"
  else
    bad "beta ${name} did not wait (rc=$rc)"; show
  fi
done

fresh; fx runs ""
rc="$(run)"
if [ "$rc" = "0" ] && ! mutated && grep -q 'waiting' "$work/stdout"; then
  ok "no run yet: waits, and with auto-merge already off makes no calls"
else
  bad "no-run case wrong (rc=$rc)"; show
fi

echo "--- lookup failures never let the PR through ---"
fresh; : > "$FX/prs.rc"
rc="$(run)"
if [ "$rc" = "1" ] && grep -q '::error title=release-beta-gate indeterminate::could not list' "$work/stdout" && ! mutated; then
  ok "a failed PR lookup fails the run visibly"
else
  bad "PR lookup failure wrong (rc=$rc)"; show
fi

for broken in parent code.main9 runs code.main code.main10 jobs.901 ownruns; do
  fresh; fx prs $'42\thead1\tfalse\ttrue\t'
  fx runs $'902\tmain10\n901\tapp5'; fx code.main10 app5
  fx jobs.902 "$(beta completed cancelled)"; fx jobs.901 "$(beta completed success)"
  if [ "$broken" = ownruns ]; then fx runs $'902\tmain10'; fx ownruns 901; fi
  : > "$FX/${broken}.rc"
  rc="$(run)"
  if [ "$rc" = "1" ] && disabled && ! enabled; then
    ok "${broken} lookup fails: the run fails visibly and auto-merge is turned off"
  else
    bad "${broken} failure wrong (rc=$rc)"; show
  fi
done

fresh; fx prs ""
rc="$(run)"
if [ "$rc" = "0" ] && [ "$(wc -l <"$work/log")" = "1" ] && grep -q 'No open release PR' "$work/stdout"; then
  ok "no open release PR: one lookup, nothing else"
else
  bad "no-PR case wrong (rc=$rc)"; show
fi

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails" >&2; exit 1; fi
echo "ALL PASS"
