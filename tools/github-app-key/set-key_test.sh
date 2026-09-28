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

# Hermetic test for set-key.sh: a fake `gh` on PATH, a throwaway RSA key made
# with openssl, no network and no credentials. What matters most: a key is only
# ever stored after every check passes, and its contents never reach stdout.

set -uo pipefail

UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/set-key.sh"
[ -f "${UNDER_TEST}" ] || { echo "cannot find set-key.sh" >&2; exit 1; }

PASS=0; FAIL=0
check() { # check <name> <0 = pass>
  if [ "$2" = "0" ]; then printf '  PASS  %s\n' "$1"; PASS=$((PASS+1))
  else printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); fi
}

WORK="$(mktemp -d "${TEST_TMPDIR:-/tmp}/github-app-key.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${WORK}/bin" "${WORK}/dl"

# Fake gh. Behaviour comes from env vars; every `secret set` is logged along
# with a copy of what it received on stdin.
cat > "${WORK}/bin/gh" <<'FAKE'
#!/usr/bin/env bash
args="$*"
case "$args" in
  "auth status"*) exit 0 ;;
  *"secret set"*)
    n=$(( $(ls "${FAKE_LOG}".stdin.* 2>/dev/null | wc -l) + 1 ))
    cat > "${FAKE_LOG}.stdin.${n}"
    echo "$args" >> "${FAKE_LOG}"
    exit 0 ;;
  *"Authorization: Bearer"*"/app --jq .slug"*)
    [ "${FAKE_REJECT:-0}" = 1 ] && exit 1
    echo "${FAKE_SLUG}" ;;
  *"Authorization: Bearer"*"/app --jq .id"*) echo "${FAKE_APP_ID}" ;;
  *"Authorization: Bearer"*"/installation"*) [ "${FAKE_INSTALLED:-1}" = 1 ] || exit 1; echo 42 ;;
  *"rulesets --jq"*) echo 17645603 ;;
  *"rulesets/17645603 --jq"*) printf '%s\n' ${FAKE_BYPASS:-} ;;
  *) echo "fake gh: unexpected: $args" >&2; exit 99 ;;
esac
FAKE
chmod +x "${WORK}/bin/gh"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "${WORK}/key.pem" 2>/dev/null

# run <pem-or-empty> <app> [extra args...] -> sets OUT, RC; fresh log and pem copy each time
run() {
  local pem="$1"; shift
  rm -f "${WORK}"/log* "${WORK}"/dl/*
  export FAKE_LOG="${WORK}/log"
  local args=("$@" --yes)
  if [ -n "$pem" ]; then cp "${WORK}/key.pem" "$pem"; args+=(--pem "$pem"); fi
  OUT="$(PATH="${WORK}/bin:${PATH}" GITHUB_APP_KEY_DOWNLOADS="${WORK}/dl" bash "${UNDER_TEST}" "${args[@]}" 2>&1)"; RC=$?
}
t() { if "$@"; then echo 0; else echo 1; fi; }
stored() { [ -f "${WORK}/log" ] && wc -l <"${WORK}/log" | tr -d ' ' || echo 0; }
key_leaked() { grep -q "$(sed -n 2p "${WORK}/key.pem")" <<<"$OUT"; }

echo "set-key.sh"

# 1. happy path: renovate
export FAKE_SLUG=vitruvian-renovate FAKE_APP_ID=5112449 FAKE_BYPASS=3863936 FAKE_REJECT=0 FAKE_INSTALLED=1
run "${WORK}/dl/vitruvian-renovate.2026-09-28.private-key.pem" renovate
check "renovate: succeeds" "$RC"
check "renovate: stores exactly one secret" "$(t [ "$(stored)" = 1 ])"
check "renovate: secret is RENOVATE_APP_PRIVATE_KEY on the repo" "$(grep -q 'secret set RENOVATE_APP_PRIVATE_KEY --repo VitruvianSoftware/vitruvian-core$' "${WORK}/log"; echo $?)"
check "renovate: the stored value is the key file, via stdin" "$(cmp -s "${WORK}/key.pem" "${WORK}/log.stdin.1"; echo $?)"
check "renovate: key contents never printed" "$(key_leaked && echo 1 || echo 0)"
check "renovate: .pem deleted after storing (--yes)" "$(t [ ! -e "${WORK}/dl/vitruvian-renovate.2026-09-28.private-key.pem" ])"

# 2. finds the newest download when --pem is omitted
rm -f "${WORK}"/dl/*
cp "${WORK}/key.pem" "${WORK}/dl/vitruvian-renovate.2026-09-28.private-key.pem"
export FAKE_LOG="${WORK}/log"; rm -f "${WORK}"/log*
OUT="$(PATH="${WORK}/bin:${PATH}" GITHUB_APP_KEY_DOWNLOADS="${WORK}/dl" bash "${UNDER_TEST}" renovate --yes 2>&1)"; RC=$?
check "auto-finds ~/Downloads/<slug>.*.private-key.pem" "$RC"

# 3-7. every failed check stores nothing
fails_and_stores_nothing() { # <name>
  check "$1: exits non-zero" "$(t [ "$RC" != 0 ])"
  check "$1: stores nothing" "$(t [ "$(stored)" = 0 ])"
}
FAKE_SLUG=vitruvian-copybara-sync run "${WORK}/k.pem" renovate;      fails_and_stores_nothing "key for a different App"
FAKE_REJECT=1 run "${WORK}/k.pem" renovate;                          fails_and_stores_nothing "key GitHub rejects"
FAKE_INSTALLED=0 run "${WORK}/k.pem" renovate;                       fails_and_stores_nothing "App not installed"
FAKE_BYPASS="3863936 5112449" run "${WORK}/k.pem" renovate;          fails_and_stores_nothing "renovate on a bypass list"
echo "not a key" > "${WORK}/bad.pem"
rm -f "${WORK}"/log*; OUT="$(PATH="${WORK}/bin:${PATH}" bash "${UNDER_TEST}" renovate --pem "${WORK}/bad.pem" --yes 2>&1)"; RC=$?
fails_and_stores_nothing "file is not a private key"

# 8. copybara-sync: IS a bypass actor by design, and goes to both stores
FAKE_SLUG=vitruvian-copybara-sync FAKE_APP_ID=3863936 run "${WORK}/k.pem" copybara-sync
check "copybara-sync: succeeds despite being a bypass actor" "$RC"
check "copybara-sync: Actions secret" "$(grep -q 'secret set SYNC_APP_PRIVATE_KEY --repo VitruvianSoftware/vitruvian-core$' "${WORK}/log"; echo $?)"
check "copybara-sync: Dependabot secret" "$(grep -q 'secret set SYNC_APP_PRIVATE_KEY --repo VitruvianSoftware/vitruvian-core --app dependabot$' "${WORK}/log"; echo $?)"

# 9. unknown app
run "" no-such-app
check "unknown app: exits non-zero" "$(t [ "$RC" != 0 ])"

echo "${PASS} passed, ${FAIL} failed"
[ "${FAIL}" = 0 ]
