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

# Hermetic guard for tools/ci/deploy-affected.sh. Uses a REAL temp git repo
# (no faking needed for step 1/2/3 -- `git diff` is the thing under test) and a
# fake target-determinator binary (TD_BIN test hook, tools/ci/td-lib.sh) only
# for the graph-mode step 4 cases. Pins the FAIL-OPEN invariant (every
# uncertain path deploys) AND the new path-only mode (#1351: needed so
# oauth-user-inspector-deploy can gate via this script without a Bazel graph).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/deploy-affected.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

repo="$work/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

# commit_file <path> <content> — writes one commit touching exactly one file
# on top of current HEAD; echoes the commit sha BEFORE it (the correct
# BEFORE_REV for a test that wants to see ONLY this commit's diff).
commit_file() {
  local before
  before="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo "")"
  mkdir -p "$repo/$(dirname "$1")"
  printf '%s\n' "$2" > "$repo/$1"
  git -C "$repo" add "$1"
  # A no-op commit (identical path+content reused across two test cases) would
  # make `git commit` fail and leak its stdout into this function's captured
  # output, corrupting the returned "before" sha — fail loudly instead.
  if ! git -C "$repo" commit -q -m "add $1" >/dev/null 2>&1; then
    echo "commit_file: '$1' produced no change — reused path+content across two test cases?" >&2
    exit 1
  fi
  printf '%s' "$before"
}

commit_file_msg() {
  local before
  before="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo "")"
  mkdir -p "$repo/$(dirname "$1")"
  printf '%s\n' "$2" > "$repo/$1"
  git -C "$repo" add "$1"
  if ! git -C "$repo" commit -q -m "$3" >/dev/null 2>&1; then
    echo "commit_file_msg: '$1' produced no change — reused path+content across two test cases?" >&2
    exit 1
  fi
  printf '%s' "$before"
}

# seed the repo with a base commit so the very first real test commit has a
# non-empty BEFORE_REV.
commit_file "README.md" "seed" >/dev/null

# fake target-determinator: prints $FAKE_TD_OUT (one target per line, or
# empty for "nothing affected"); FAKE_TD_RC forces a non-zero exit.
cat > "$work/fake-td" <<'EOF'
#!/usr/bin/env bash
if [ "${FAKE_TD_RC:-0}" != "0" ]; then echo "td: boom" >&2; exit "${FAKE_TD_RC}"; fi
[ -n "${FAKE_TD_OUT:-}" ] && printf '%s\n' "${FAKE_TD_OUT}"
exit 0
EOF
chmod +x "$work/fake-td"

# run <before_rev> [env...] — prints the affected= value written to
# $GITHUB_OUTPUT. Runs from inside the fixture repo (the script shells out to
# plain `git`, which resolves against CWD).
run() {
  local before="$1"; shift
  local out="$work/out"; : > "$out"
  ( cd "$repo" && env GITHUB_OUTPUT="$out" BEFORE_REV="$before" TD_BIN="$work/fake-td" \
      BUILDBUDDY_API_KEY=unused "$@" bash "$SCRIPT" ) >"$work/stdout" 2>"$work/stderr"
  sed -n 's/^affected=//p' "$out"
}

expect() { # <label> <before_rev> <want-affected> [env...]
  local label="$1" before="$2" want="$3"; shift 3
  local got; got="$(run "$before" "$@")"
  if [ "$got" = "$want" ]; then pass "$label (affected=$got)"; else
    fail "$label — got '$got', want '$want'"
    sed 's/^/      stderr: /' "$work/stderr" >&2
  fi
}

echo "--- fail-open basics ---"
sha1="$(commit_file "app/a.txt" "1")"
expect "forced push always deploys" "$sha1" true FORCED_PUSH=true DEPLOY_TARGETS="//x"
expect "empty BEFORE_REV deploys" "" true DEPLOY_TARGETS="//x"
expect "garbage BEFORE_REV deploys" "not-a-sha" true DEPLOY_TARGETS="//x"

echo "--- no-op diff ---"
head_now="$(git -C "$repo" rev-parse HEAD)"
expect "no changed files vs HEAD itself" "$head_now" false DEPLOY_TARGETS="//x" FAKE_TD_OUT=""

echo "--- step 2: EXTRA_PATH_REGEX (graph mode, short-circuits before TD) ---"
sha2="$(commit_file "tabula/infra/app/main.go" "x")"
expect "extra-path match deploys without ever touching TD" "$sha2" true \
  DEPLOY_TARGETS="//x" EXTRA_PATH_REGEX='tabula/infra/app/' FAKE_TD_RC=1

echo "--- step 2: EXCLUDE_PATH_REGEX subtracts a match ---"
sha3="$(commit_file "oauth-user-inspector/infra/identity/x.go" "x")"
expect "excluded path does not satisfy the include, falls through to TD (empty)" "$sha3" false \
  DEPLOY_TARGETS="//x" EXTRA_PATH_REGEX='oauth-user-inspector/' EXCLUDE_PATH_REGEX='oauth-user-inspector/infra/identity/' FAKE_TD_OUT=""

echo "--- step 3: global-impact guard ---"
sha4="$(commit_file "MODULE.bazel" "x")"
expect "MODULE.bazel change is global-impact" "$sha4" true DEPLOY_TARGETS="//x" FAKE_TD_RC=1

sha5="$(commit_file "tools/ci/allowed.sh" "x")"
expect "allowlisted tools/ci/ subdir is NOT global-impact (falls to TD, empty)" "$sha5" false \
  DEPLOY_TARGETS="//x" FAKE_TD_OUT=""

sha6="$(commit_file "tools/randomdir/x.sh" "x")"
expect "non-allowlisted tools/ subdir IS global-impact" "$sha6" true DEPLOY_TARGETS="//x" FAKE_TD_RC=1

echo "--- step 4: graph attribution ---"
sha7="$(commit_file "unrelated/z.txt" "x")"
expect "TD reports a target affected" "$sha7" true DEPLOY_TARGETS="//x" FAKE_TD_OUT="//x"
expect "TD reports nothing affected" "$sha7" false DEPLOY_TARGETS="//x" FAKE_TD_OUT=""
expect "TD error fails open" "$sha7" true DEPLOY_TARGETS="//x" FAKE_TD_RC=1

echo "--- path-only mode (DEPLOY_TARGETS unset, #1351) ---"
sha8="$(commit_file "oauth-user-inspector/app/index.ts" "x")"
expect "path-only mode: match deploys" "$sha8" true \
  EXTRA_PATH_REGEX='oauth-user-inspector/'

sha9="$(commit_file "docs/unrelated.md" "x")"
expect "path-only mode: no match skips (never touches TD)" "$sha9" false \
  EXTRA_PATH_REGEX='oauth-user-inspector/' FAKE_TD_RC=1

sha10="$(commit_file "oauth-user-inspector/infra/identity/y.go" "x")"
expect "path-only mode: excluded-only match skips" "$sha10" false \
  EXTRA_PATH_REGEX='oauth-user-inspector/' EXCLUDE_PATH_REGEX='oauth-user-inspector/infra/identity/'

sha11="$(commit_file "tools/randomdir/y.sh" "x")"
expect "path-only mode: does NOT apply the global-impact guard" "$sha11" false \
  EXTRA_PATH_REGEX='oauth-user-inspector/'

echo "--- release-please version-bump guard ---"
sha_rp1="$(commit_file_msg "oauth-user-inspector/package.json" "{\"version\":\"1.7.2\"}" "chore(main): release oauth-user-inspector 1.7.2")"
expect "release-please commit chore(main): release skips dev deploy" "$sha_rp1" false \
  EXTRA_PATH_REGEX='oauth-user-inspector/' FAKE_TD_RC=1

sha_rp2="$(commit_file_msg "tabula/package.json" "{\"version\":\"2.0.0\"}" "chore(release): release tabula 2.0.0")"
expect "release-please commit chore(release): release skips dev deploy" "$sha_rp2" false \
  EXTRA_PATH_REGEX='tabula/' FAKE_TD_RC=1

sha_normal="$(commit_file_msg "oauth-user-inspector/app/foo.ts" "x" "feat(oauth): update login feature")"
expect "normal feature commit matching path deploys" "$sha_normal" true \
  EXTRA_PATH_REGEX='oauth-user-inspector/' FAKE_TD_RC=1

# The guard's premise ("functional code already deployed on feature PR merge")
# holds only when the RANGE IS the single release commit. BEFORE_REV is the
# durable base, which does NOT advance past an evicted or failed run -- so a
# range routinely accumulates real commits behind a release bump at HEAD.
# Judging it by HEAD's subject alone silently discards them, and since the run
# then concludes success the base advances and they are skipped forever.
# Reproduces live run 32363502989 (afc7e5c1..c0639105).
base_mixed="$(git -C "$repo" rev-parse HEAD)"
commit_file_msg "oauth-user-inspector/app/real-change.ts" "x" "feat(oauth): a real change that must deploy" >/dev/null
commit_file_msg "oauth-user-inspector/package.json" "{\"version\":\"1.7.3\"}" "chore(main): release oauth-user-inspector 1.7.3" >/dev/null
expect "release bump at HEAD does NOT dismiss real commits behind it" "$base_mixed" true \
  EXTRA_PATH_REGEX='oauth-user-inspector/' FAKE_TD_RC=1

# ...and the guard still fires when the range is ONLY release commits, however
# many of them (a release burst coalesced into one push range).
base_allrp="$(git -C "$repo" rev-parse HEAD)"
commit_file_msg "tabula/package.json" "{\"version\":\"2.0.1\"}" "chore(main): release tabula 2.0.1" >/dev/null
commit_file_msg "tabula/extension/package.json" "{\"version\":\"0.1.38\"}" "chore(main): release tabula-extension 0.1.38" >/dev/null
expect "an all-release-commit range still skips" "$base_allrp" false \
  EXTRA_PATH_REGEX='tabula/' FAKE_TD_RC=1

echo "--- path-only mode with no signal at all: hard error, not a silent false ---"
( cd "$repo" && env GITHUB_OUTPUT="$work/out2" BEFORE_REV="$sha11" bash "$SCRIPT" ) >/dev/null 2>"$work/stderr2"
guard_rc=$?
if [ "$guard_rc" -ne 0 ] && grep -q "no affected signal at all" "$work/stderr2"; then
  pass "DEPLOY_TARGETS and EXTRA_PATH_REGEX both unset exits non-zero (not a silent affected=false)"
else
  fail "DEPLOY_TARGETS and EXTRA_PATH_REGEX both unset — expected non-zero exit with the no-signal message, got rc=$guard_rc"
fi

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails" >&2; exit 1; fi
echo "ALL PASS"
