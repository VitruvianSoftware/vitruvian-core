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

# secret-scan_test.sh — //tools/secret-scan finds a secret where CI would, names
# the file and line without printing the secret, and never calls a scan that did
# not run "clean". Uses the real pinned gitleaks and the repo's .gitleaks.toml,
# found through runfiles exactly as `bazel run` finds them, in throwaway repos.
set -uo pipefail

SCRIPT="${1:?usage: secret-scan_test.sh <secret-scan.sh|secret-scan binary> <ci secret-scan.sh> <tools.lock.json>}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
CI_SCRIPT="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
LOCK="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"

work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$work"' EXIT
pass_n=0
fail_n=0
pass() { echo "  ✓ $1"; pass_n=$((pass_n + 1)); }
fail() { echo "  ✗ $1" >&2; fail_n=$((fail_n + 1)); }

export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# A value gitleaks' generic-api-key rule flags. Built from short pieces so this
# file holds nothing a scan of the repo itself would flag.
SECRET="Zq8Lm3Rt""7Vx2Kp9W""n4Hs6Jd1""Fg5Bc0Ya"
plant() { printf 'first line\napi_token = "%s"\n' "$SECRET" >"$1"; }

new_repo() { # <dir>: a repo with one commit on main and origin/main beside it
    git init -q -b main "$1"
    git -C "$1" commit -q --allow-empty -m base
    git -C "$1" update-ref refs/remotes/origin/main refs/heads/main
}
# $1 may also be a compiled port (//tools/secret-scan:secret-scan): a script
# runs under bash, a binary as itself.
scan() {
    case "$SCRIPT" in
        *.sh) (cd "$work" && BUILD_WORKSPACE_DIRECTORY="$repo" bash "$SCRIPT" "$@") ;;
        *) (cd "$work" && BUILD_WORKSPACE_DIRECTORY="$repo" "$SCRIPT" "$@") ;;
    esac
}

repo="$work/repo"
new_repo "$repo"

# 1. Nothing staged that looks like a secret: clean, exit 0.
echo hello >"$repo/ok.txt"
git -C "$repo" add ok.txt
out="$(scan --staged 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q "no secrets found in the staged changes" <<<"$out"; then
    pass "--staged: clean staged changes pass"
else
    fail "--staged on clean changes (rc=$rc): $out"
fi

# 2. A staged secret: exit 1, file:line and rule named, the secret never shown.
plant "$repo/leak.txt"
git -C "$repo" add leak.txt
out="$(scan --staged 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "leak.txt:2" <<<"$out" && grep -q "rule: " <<<"$out"; then
    pass "--staged: a staged secret fails and names leak.txt:2 and its rule"
else
    fail "--staged did not report the staged secret (rc=$rc): $out"
fi
if grep -qF "$SECRET" <<<"$out" || grep -qF "${SECRET:0:12}" <<<"$out"; then
    fail "the secret was printed: $out"
else
    pass "the secret itself is never printed"
fi

# 3. Branch mode (the default): the commits main does not have.
git -C "$repo" checkout -q -b feat/x
git -C "$repo" commit -q -m "add files"
out="$(scan 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "leak.txt:2" <<<"$out" && grep -q "in commit $(git -C "$repo" rev-parse --short=12 HEAD)" <<<"$out"; then
    pass "default: a secret committed on the branch fails and names the commit"
else
    fail "default branch scan missed the committed secret (rc=$rc): $out"
fi

# 4. --range: only that range. The secret is in HEAD, so HEAD..HEAD is clean.
out="$(scan --range HEAD..HEAD 2>&1)"; rc=$?
out2="$(scan --range HEAD~1..HEAD 2>&1)"; rc2=$?
if [ "$rc" -eq 0 ] && [ "$rc2" -eq 1 ]; then
    pass "--range scans just the commits named"
else
    fail "--range misbehaved (empty rc=$rc, one-commit rc=$rc2): $out / $out2"
fi

# 5. A branch with no commits of its own: nothing to scan, said plainly.
git -C "$repo" checkout -q -b feat/empty main
out="$(scan 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q "no commits of its own" <<<"$out"; then
    pass "default: a branch level with main says there is nothing to scan"
else
    fail "branch level with main (rc=$rc): $out"
fi

# 6. --unpushed: commits already on origin are not scanned again.
git init -q --bare "$work/origin.git"
git -C "$repo" remote add origin "$work/origin.git"
git -C "$repo" push -q origin main feat/x 2>/dev/null
git -C "$repo" checkout -q feat/x
out="$(scan --unpushed 2>&1)"; rc=$?
echo more >"$repo/more.txt"; git -C "$repo" add more.txt
plant "$repo/leak2.txt"; git -C "$repo" add leak2.txt
git -C "$repo" commit -q -m "more"
out2="$(scan --unpushed 2>&1)"; rc2=$?
if [ "$rc" -eq 0 ] && [ "$rc2" -eq 1 ] && grep -q "leak2.txt:2" <<<"$out2" && ! grep -q "leak.txt:2" <<<"$out2"; then
    pass "--unpushed scans only commits origin does not have"
else
    fail "--unpushed (pushed rc=$rc, new rc=$rc2): $out / $out2"
fi

# 7. The repo's rules apply: a `gitleaks:allow` line passes.
git -C "$repo" checkout -q main
printf 'api_token = "%s" # gitleaks:allow\n' "$SECRET" >"$repo/allowed.txt"
git -C "$repo" add allowed.txt
out="$(scan --staged 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    pass "a gitleaks:allow line is accepted, as in CI"
else
    fail "gitleaks:allow was not honoured (rc=$rc): $out"
fi
git -C "$repo" reset -q

# 8. A gitleaks that fails to run is exit 2 and never "no secrets found".
printf '#!/usr/bin/env bash\necho boom >&2\nexit 3\n' >"$work/broken-gitleaks"
chmod +x "$work/broken-gitleaks"
out="$(GITLEAKS="$work/broken-gitleaks" scan --staged 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "NOT a clean result" <<<"$out" && ! grep -q "no secrets found" <<<"$out"; then
    pass "a gitleaks that cannot run is exit 2, not a pass"
else
    fail "a broken gitleaks was reported as a verdict (rc=$rc): $out"
fi
out="$(GITLEAKS="$work/nope" scan --staged 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "bazel run //tools/secret-scan" <<<"$out"; then
    pass "a missing gitleaks is exit 2 and says how to run it"
else
    fail "a missing gitleaks (rc=$rc): $out"
fi

# 9. Unknown flags are usage errors.
out="$(scan --bogus 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "unknown argument" <<<"$out"; then
    pass "an unknown flag is a usage error"
else
    fail "unknown flag (rc=$rc): $out"
fi

# 10. The pinned gitleaks is the one CI downloads: same version, same Linux checksum.
ci_ver="$(sed -n 's/^GITLEAKS_VERSION="\(.*\)"/\1/p' "$CI_SCRIPT")"
ci_sha="$(sed -n 's/^GITLEAKS_SHA256="\(.*\)"/\1/p' "$CI_SCRIPT")"
lock_url="$(grep -o 'https://github.com/gitleaks/gitleaks/releases/download/[^"]*linux_x64[^"]*' "$LOCK" | head -1)"
lock_sha="$(grep -A1 -F "$lock_url" "$LOCK" | sed -n 's/.*"sha256": "\([0-9a-f]*\)".*/\1/p' | head -1)"
if [ -n "$ci_ver" ] && grep -q "/v${ci_ver}/gitleaks_${ci_ver}_linux_x64" <<<"$lock_url" && [ "$lock_sha" = "$ci_sha" ]; then
    pass "tools.lock.json pins gitleaks v$ci_ver, the version and checksum CI uses"
else
    fail "gitleaks pins drifted: CI v$ci_ver ($ci_sha), lockfile $lock_url ($lock_sha). Update both together."
fi

echo "secret-scan_test: $pass_n passed, $fail_n failed"
[ "$fail_n" -eq 0 ]
