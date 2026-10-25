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
# ENABLE_DEPENDENCY_GRAPH_BIN runs the behaviour checks against another build of
# the tool (the Rust port, :enable-dependency-graph-rs_test). The source checks
# (1, 4, 5) read the script; a binary is held to the same posture by 7, which
# watches what it actually sends.
BIN="${ENABLE_DEPENDENCY_GRAPH_BIN:-}"
if [ -n "$BIN" ]; then
  case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
  RUN=("$BIN")
else
  RUN=(bash "${UNDER_TEST}")
fi

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
  # Default to a PUBLIC repo so each test exercises the gate it is about; the
  # billing test overrides this to private.
  *.visibility*)           echo "\${FAKE_VISIBILITY:-public}"; exit 0 ;;
  *code-security/configurations*) echo ""; exit 0 ;;
  *) echo ""; exit 0 ;;
esac
EOF
  chmod +x "${bin}/gh"
}

echo "enable-dependency-graph_test:"

# --- 1. syntax. --------------------------------------------------------------
if [ -z "$BIN" ]; then
  bash -n "${UNDER_TEST}" 2>/dev/null; check "script parses" "$?"
fi

# --- 2. idempotence: graph already on -> no-op, and NOTHING is mutated. ------
tmp="$(mktemp -d)"; make_fake_gh "${tmp}" 0
out="$(PATH="${tmp}:${PATH}" "${RUN[@]}" 2>&1)"; rc=$?
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
out="$(PATH="${tmp}:${PATH}" "${RUN[@]}" </dev/null 2>&1)"; rc=$?
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
# Exactly TWO settings may be 'enabled': dependency_graph (what we want) and
# advanced_security (which the API demands as its gate -- a config enabling any
# GHAS feature without it is rejected with HTTP 422). advanced_security turns on
# no feature by itself while every real feature below stays not_set.
if [ -z "$BIN" ]; then
enabled_count="$(grep -cE "^ *-f [a-z_]+='enabled'" "${UNDER_TEST}" || true)"
check "exactly two settings are 'enabled'" "$([ "${enabled_count}" = "2" ] && echo 0 || echo 1)"
grep -qE "^ *-f dependency_graph='enabled'" "${UNDER_TEST}"; check "...dependency_graph is one" "$?"
grep -qE "^ *-f advanced_security='enabled'" "${UNDER_TEST}"; check "...advanced_security is the other (API gate)" "$?"
for f in dependabot_alerts dependabot_security_updates secret_scanning secret_scanning_push_protection code_scanning_default_setup private_vulnerability_reporting; do
  grep -qE "^ *-f ${f}='not_set'" "${UNDER_TEST}"; check "${f} left not_set" "$?"
done

# --- 5. blast radius: attach to selected repos only, never the whole org. ----
grep -q "scope='selected'" "${UNDER_TEST}"; check "attaches with scope=selected" "$?"
if grep -qE "scope='all'" "${UNDER_TEST}"; then check "never attaches org-wide" 1; else check "never attaches org-wide" 0; fi
fi

# --- 6. billing guard: must REFUSE a non-public repo without confirmation. ----
# advanced_security is free on public repos but BILLS PER COMMITTER on private
# ones, and the API will not let us omit it. A silent enable would be a real
# invoice.
tmp="$(mktemp -d)"; make_fake_gh "${tmp}" 1
out="$(FAKE_VISIBILITY=private PATH="${tmp}:${PATH}" "${RUN[@]}" </dev/null 2>&1)"; rc=$?
check "private repo refused without a TTY" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
case "${out}" in *"BILLS PER ACTIVE COMMITTER"*|*"billable"*|*"BILL"*) check "private refusal names the billing risk" 0 ;; *) check "private refusal names the billing risk" 1 ;; esac
if grep -qE 'POST' "${tmp}/calls.log" 2>/dev/null; then check "private repo mutates nothing" 1; else check "private repo mutates nothing" 0; fi
rm -rf "${tmp}"

# --- 7. what is SENT: the full run, as an admin:org holder, on a public repo. --
# The graph comes online once the configuration is attached. The POST must
# carry exactly the posture above, the attach must be scope=selected for this
# one repo, and nothing else may be written. (Checks 4 and 5 read the script;
# this one holds any build of the tool to the same line.)
tmp="$(mktemp -d)"
cat > "${tmp}/gh" <<FAKEGH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${tmp}/calls.log"
case "\$*" in
  *dependency-graph/sbom*) grep -q '/attach' "${tmp}/calls.log" && exit 0; exit 1 ;;
  *"-i user"*)             printf 'HTTP/2.0 200 OK\r\nX-Oauth-Scopes: repo, admin:org\r\n\r\n{}\n'; exit 0 ;;
  *.visibility*)           echo public ;;
  *"-X POST"*"/attach"*)   echo '{}' ;;
  *"-X POST"*)             echo 99 ;;
  *"--jq .id"*)            echo 4242 ;;
  *)                       echo "" ;;
esac
FAKEGH
chmod +x "${tmp}/gh"
printf '#!/usr/bin/env bash\nexit 0\n' > "${tmp}/sleep"; chmod +x "${tmp}/sleep"
out="$(PATH="${tmp}:${PATH}" "${RUN[@]}" </dev/null 2>&1)"; rc=$?
check "full run succeeds" "$([ "${rc}" = "0" ] && echo 0 || echo 1)"
case "${out}" in *"ENABLED and answering"*) check "full run confirms the graph answers" 0 ;; *) check "full run confirms the graph answers" 1 ;; esac
post="$(grep -- '-X POST orgs/VitruvianSoftware/code-security/configurations -f' "${tmp}/calls.log" || true)"
want="-f advanced_security=enabled -f dependency_graph=enabled -f dependabot_alerts=not_set -f dependabot_security_updates=not_set -f secret_scanning=not_set -f secret_scanning_push_protection=not_set -f code_scanning_default_setup=not_set -f private_vulnerability_reporting=not_set --jq .id"
case "${post}" in *"${want}") check "the POST enables only the graph (and its gate)" 0 ;; *) check "the POST enables only the graph (and its gate): ${post}" 1 ;; esac
case "${post}" in *"-f name=dependency-graph-only -f description="*) check "...as the dependency-graph-only configuration" 0 ;; *) check "...as the dependency-graph-only configuration" 1 ;; esac
grep -qxF -- 'api -X POST orgs/VitruvianSoftware/code-security/configurations/99/attach -f scope=selected -F selected_repository_ids[]=4242' "${tmp}/calls.log" 2>/dev/null
check "attaches to this repository only (scope=selected)" "$?"
check "writes nothing else" "$([ "$(grep -c -- '-X POST' "${tmp}/calls.log")" = 2 ] && echo 0 || echo 1)"
rm -rf "${tmp}"

echo
if [ "${FAIL}" -ne 0 ]; then
  printf '\033[31mFAIL\033[0m — %d passed, %d failed\n' "${PASS}" "${FAIL}"; exit 1
fi
printf '\033[32mPASS\033[0m — %d passed\n' "${PASS}"
