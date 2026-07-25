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

# Hermetic self-test for enable-dependency-graph.sh: a fake `gh` on PATH, no
# network, no credentials, no TTY. Pins the two behaviours that actually matter
# -- it must be idempotent, and it must never widen the org's security posture
# beyond the dependency graph.

set -uo pipefail

UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/enable-dependency-graph.sh"
[ -f "${UNDER_TEST}" ] || { echo "cannot find enable-dependency-graph.sh" >&2; exit 1; }

PASS=0; FAIL=0
check() { # check <name> <condition-result>
  if [ "$2" = "0" ]; then printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1))
  else printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); fi
}

# fake_gh <sbom-exit-code> — writes a `gh` stub that records every invocation.
make_fake_gh() {
  bin="$1"; sbom_rc="$2"
  mkdir -p "${bin}"
  cat > "${bin}/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${bin}/calls.log"
case "\$*" in
  *dependency-graph/sbom*) exit ${sbom_rc} ;;
  *"-i user"*)             echo "x-oauth-scopes: gist, read:org, repo, workflow"; exit 0 ;;
  *code-security/configurations*) echo ""; exit 0 ;;
  *) echo ""; exit 0 ;;
esac
EOF
  chmod +x "${bin}/gh"
}

echo "enable-dependency-graph_test:"

# --- 1. syntax. --------------------------------------------------------------
bash -n "${UNDER_TEST}" 2>/dev/null; check "script parses" "$?"

# --- 2. idempotence: graph already on -> no-op, and NOTHING is mutated. ------
tmp="$(mktemp -d)"; make_fake_gh "${tmp}" 0
out="$(PATH="${tmp}:${PATH}" bash "${UNDER_TEST}" 2>&1)"; rc=$?
check "already-enabled exits 0" "$([ "${rc}" = "0" ] && echo 0 || echo 1)"
case "${out}" in *"already enabled"*) check "already-enabled says so" 0 ;; *) check "already-enabled says so" 1 ;; esac
# The decisive assertion: it must not create or attach anything.
if grep -qE 'POST|attach|configurations' "${tmp}/calls.log" 2>/dev/null; then
  check "already-enabled mutates nothing" 1
else
  check "already-enabled mutates nothing" 0
fi
rm -rf "${tmp}"

# --- 3. no TTY + missing admin:org -> refuses loudly, mutates nothing. -------
# A silent proceed here would be the dangerous failure: a half-applied config.
tmp="$(mktemp -d)"; make_fake_gh "${tmp}" 1
out="$(PATH="${tmp}:${PATH}" bash "${UNDER_TEST}" </dev/null 2>&1)"; rc=$?
check "no-TTY without admin:org fails" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
case "${out}" in *"interactive shell"*) check "no-TTY explains the fix" 0 ;; *) check "no-TTY explains the fix" 1 ;; esac
if grep -qE 'POST' "${tmp}/calls.log" 2>/dev/null; then
  check "no-TTY mutates nothing" 1
else
  check "no-TTY mutates nothing" 0
fi
rm -rf "${tmp}"

# --- 4. posture: the configuration must widen NOTHING but the graph. ---------
# Guards against a future edit flipping one of these to `enabled` and silently
# taking ownership of a setting repo_config/Pulumi manages.
enabled_count="$(grep -cE "^ *-f [a-z_]+='enabled'" "${UNDER_TEST}" || true)"
check "exactly one setting is 'enabled'" "$([ "${enabled_count}" = "1" ] && echo 0 || echo 1)"
grep -qE "^ *-f dependency_graph='enabled'" "${UNDER_TEST}"; check "...and it is dependency_graph" "$?"
for f in dependabot_alerts dependabot_security_updates secret_scanning secret_scanning_push_protection code_scanning_default_setup private_vulnerability_reporting; do
  grep -qE "^ *-f ${f}='not_set'" "${UNDER_TEST}"; check "${f} left not_set" "$?"
done

# --- 5. blast radius: attach to selected repos only, never the whole org. ----
grep -q "scope='selected'" "${UNDER_TEST}"; check "attaches with scope=selected" "$?"
if grep -qE "scope='all'" "${UNDER_TEST}"; then check "never attaches org-wide" 1; else check "never attaches org-wide" 0; fi

echo
if [ "${FAIL}" -ne 0 ]; then
  printf '\033[31mFAIL\033[0m — %d passed, %d failed\n' "${PASS}" "${FAIL}"; exit 1
fi
printf '\033[32mPASS\033[0m — %d passed\n' "${PASS}"
