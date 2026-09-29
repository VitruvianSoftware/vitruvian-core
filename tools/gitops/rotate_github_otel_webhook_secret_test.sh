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

# Hermetic test for rotate_github_otel_webhook_secret.sh: fake kubectl,
# kubeseal and gh on PATH, a throwaway workspace. The secret must be identical
# in the sealed file and both GitHub stores, must never reach stdout, and a
# failure must leave no sealed file behind.

set -uo pipefail

UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rotate_github_otel_webhook_secret.sh"
[ -f "${UNDER_TEST}" ] || { echo "cannot find rotate_github_otel_webhook_secret.sh" >&2; exit 1; }

PASS=0; FAIL=0
check() { if [ "$2" = "0" ]; then printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); else printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); fi; }
t() { if "$@"; then echo 0; else echo 1; fi; }

WORK="$(mktemp -d "${TEST_TMPDIR:-/tmp}/rotate-otel.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${WORK}/bin" "${WORK}/ws/gitops/argocd/platform/sealed-secrets-manifests"
export W="${WORK}"
OUT_REL="gitops/argocd/platform/sealed-secrets-manifests/github-otel-webhook.sealedsecret.yaml"

# Fake kubectl: `create secret generic ... --from-file=KEY=/dev/stdin` -> a
# Secret manifest whose data carries the value (base64), as the real one does.
cat > "${WORK}/bin/kubectl" <<'FAKE'
#!/usr/bin/env bash
v="$(cat)"; printf '%s' "$v" > "${W}/kubectl-got"
printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: github-otel-webhook\n  namespace: cicd-telemetry\ndata:\n  GITHUB_WEBHOOK_SECRET: %s\n' "$(printf '%s' "$v" | base64 | tr -d '\n')"
FAKE
# Fake kubeseal: turns the Secret into a SealedSecret; "encrypts" by copying.
cat > "${WORK}/bin/kubeseal" <<'FAKE'
#!/usr/bin/env bash
[ "${FAKE_KUBESEAL_FAIL:-0}" = 1 ] && { cat >/dev/null; exit 1; }
sed 's/^kind: Secret/kind: SealedSecret/; s/^apiVersion: v1/apiVersion: bitnami.com\/v1alpha1/'
FAKE
cat > "${WORK}/bin/gh" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "auth status"*) exit 0 ;;
  *"secret set"*)
    [ "${FAKE_GH_FAIL:-0}" = 1 ] && { cat >/dev/null; exit 1; }
    n=$(( $(ls "${W}"/gh-stdin.* 2>/dev/null | wc -l) + 1 ))
    cat > "${W}/gh-stdin.${n}"; echo "$*" >> "${W}/gh-log" ;;
  *) echo "fake gh: unexpected: $*" >&2; exit 99 ;;
esac
FAKE
chmod +x "${WORK}"/bin/*

run() { # -> OUT, RC
  rm -f "${WORK}"/gh-* "${WORK}/kubectl-got" "${WORK}/ws/${OUT_REL}"
  OUT="$(cd "${WORK}/ws" && PATH="${WORK}/bin:${PATH}" BUILD_WORKSPACE_DIRECTORY="${WORK}/ws" bash "${UNDER_TEST}" 2>&1)"; RC=$?
}

echo "rotate_github_otel_webhook_secret.sh"

run
check "succeeds" "$RC"
SECRET="$(cat "${WORK}/kubectl-got" 2>/dev/null)"
check "secret is 64 hex chars" "$(t grep -qE '^[0-9a-f]{64}$' <<<"${SECRET}")"
check "sealed file written" "$(t [ -f "${WORK}/ws/${OUT_REL}" ])"
check "sealed file has the license header" "$(t grep -q 'Copyright (c) 2026 VitruvianSoftware' "${WORK}/ws/${OUT_REL}")"
check "sealed file targets cicd-telemetry/github-otel-webhook" "$(t grep -q 'namespace: cicd-telemetry' "${WORK}/ws/${OUT_REL}")"
check "Actions store got the same secret" "$(t cmp -s <(printf '%s' "${SECRET}") "${WORK}/gh-stdin.1")"
check "Dependabot store got the same secret" "$(t cmp -s <(printf '%s' "${SECRET}") "${WORK}/gh-stdin.2")"
check "Actions store name + repo" "$(t grep -qx 'secret set GITHUB_OTEL_WEBHOOK_SECRET --repo VitruvianSoftware/vitruvian-core' "${WORK}/gh-log")"
check "Dependabot store name + repo" "$(t grep -qx 'secret set GITHUB_OTEL_WEBHOOK_SECRET --repo VitruvianSoftware/vitruvian-core --app dependabot' "${WORK}/gh-log")"
check "secret never printed" "$( [ -n "${SECRET}" ] && grep -qF "${SECRET}" <<<"${OUT}" && echo 1 || echo 0)"

FAKE_KUBESEAL_FAIL=1 run
check "kubeseal fails: exits non-zero" "$(t [ "$RC" != 0 ])"
check "kubeseal fails: nothing sent to GitHub" "$(t [ ! -e "${WORK}/gh-log" ])"
check "kubeseal fails: no sealed file" "$(t [ ! -e "${WORK}/ws/${OUT_REL}" ])"

FAKE_GH_FAIL=1 run
check "gh fails: exits non-zero" "$(t [ "$RC" != 0 ])"
check "gh fails: no sealed file (git and GitHub can't disagree)" "$(t [ ! -e "${WORK}/ws/${OUT_REL}" ])"

echo "${PASS} passed, ${FAIL} failed"
[ "${FAIL}" = 0 ]
