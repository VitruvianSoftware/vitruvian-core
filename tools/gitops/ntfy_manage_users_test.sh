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

# Hermetic test for ntfy_manage_users.sh change-pass --gh-secret: fake kubectl,
# gh and curl on PATH. The pod, the repo secret and the live-server check must
# all see the SAME new password, and it must never reach stdout.

set -uo pipefail

UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ntfy_manage_users.sh"
[ -f "${UNDER_TEST}" ] || { echo "cannot find ntfy_manage_users.sh" >&2; exit 1; }

PASS=0; FAIL=0
check() { # check <name> <0 = pass>
  if [ "$2" = "0" ]; then printf '  PASS  %s\n' "$1"; PASS=$((PASS+1))
  else printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); fi
}
t() { if "$@"; then echo 0; else echo 1; fi; }

WORK="$(mktemp -d "${TEST_TMPDIR:-/tmp}/ntfy-users.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${WORK}/bin"
export W="${WORK}"

cat > "${WORK}/bin/kubectl" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  *"get pods"*) echo ntfy-0 ;;
  *"ntfy user list"*) printf 'user alertmanager (role: user, tier: none)\n' >&2
                      [ "${FAKE_NO_USER:-0}" = 1 ] || printf 'user github-actions (role: user, tier: none)\n' >&2 ;;
  *"ntfy user change-pass"*) head -n1 > "${W}/pod-pass"; echo "changed" >> "${W}/calls" ;;
  *) echo "fake kubectl: unexpected: $*" >&2; exit 99 ;;
esac
FAKE
cat > "${WORK}/bin/gh" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "auth status"*) exit 0 ;;
  *"secret set"*) [ "${FAKE_GH_FAIL:-0}" = 1 ] && exit 1
                  cat > "${W}/gh-pass"; echo "$*" > "${W}/gh-args"; echo "stored" >> "${W}/calls" ;;
  *) echo "fake gh: unexpected: $*" >&2; exit 99 ;;
esac
FAKE
cat > "${WORK}/bin/curl" <<'FAKE'
#!/usr/bin/env bash
cfg="$(cat)"; echo "$*" > "${W}/curl-args"
[ "${FAKE_SERVER_REJECTS:-0}" = 1 ] && exit 22
[ "$cfg" = "user = \"github-actions:$(cat "${W}/pod-pass")\"" ] || exit 22
FAKE
chmod +x "${WORK}"/bin/*

run() { # -> OUT, RC
  rm -f "${WORK}"/{pod-pass,gh-pass,gh-args,curl-args,calls}
  OUT="$(PATH="${WORK}/bin:${PATH}" bash "${UNDER_TEST}" change-pass github-actions --gh-secret NTFY_GITHUB_ACTIONS_PASSWORD 2>/dev/null)"; RC=$?
}

echo "ntfy_manage_users.sh change-pass --gh-secret"

run
check "succeeds" "$RC"
check "pod and repo secret got the same password" "$(t cmp -s <(tr -d '\n' <"${WORK}/pod-pass") "${WORK}/gh-pass")"
check "password is 32 characters" "$(t [ "$(wc -c <"${WORK}/gh-pass" | tr -d ' ')" = 32 ])"
check "stored as NTFY_GITHUB_ACTIONS_PASSWORD on the repo" "$(grep -q 'secret set NTFY_GITHUB_ACTIONS_PASSWORD --repo VitruvianSoftware/vitruvian-core' "${WORK}/gh-args"; echo $?)"
check "live check hits /v1/account" "$(grep -q 'https://ntfy.ipv1337.dev/v1/account' "${WORK}/curl-args"; echo $?)"
check "password not on curl's command line" "$(grep -qF "$(cat "${WORK}/gh-pass")" "${WORK}/curl-args" && echo 1 || echo 0)"
check "password never printed" "$(t [ -z "$OUT" ])"

FAKE_NO_USER=1 run
check "missing user: exits non-zero" "$(t [ "$RC" != 0 ])"
check "missing user: password untouched" "$(t [ ! -e "${WORK}/calls" ])"

FAKE_GH_FAIL=1 run
check "secret store fails: exits non-zero" "$(t [ "$RC" != 0 ])"

FAKE_SERVER_REJECTS=1 run
check "server rejects new password: exits non-zero" "$(t [ "$RC" != 0 ])"

# Plain change-pass (no --gh-secret) keeps its old behaviour: prints once.
rm -f "${WORK}"/{pod-pass,calls}
OUT="$(PATH="${WORK}/bin:${PATH}" bash "${UNDER_TEST}" change-pass someone 2>/dev/null)"; RC=$?
check "plain change-pass: still prints the new password once" "$(grep -qF "$(cat "${WORK}/pod-pass")" <<<"$OUT"; echo $?)"

echo "${PASS} passed, ${FAIL} failed"
[ "${FAIL}" = 0 ]
