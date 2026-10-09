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

# Guard for the last line .claude/kube-setup.sh prints: whether the homelab
# apiserver actually answers. That line is the only cluster status an agent sees
# at session start (Claude Code adds a SessionStart hook's stdout to the session
# and hides stderr from a hook that exits 0), and it once said "reachable"
# unconditionally while the tailnet had rejected TS_AUTHKEY.
#
# Runs the real hook against fake `tailscale` and `kubectl` binaries and checks,
# for each state, what it says on stdout: reachable only when kubectl got an
# answer; otherwise NOT reachable with the reason; always exit 0; and the
# ServiceAccount token never printed. Also checks it waits for a tailscale-up.sh
# that is still joining, and that the session-start hook runs it.

set -uo pipefail

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
HOOK="${ROOT}/.claude/kube-setup.sh"
SETTINGS="${ROOT}/.claude/settings.json"
TOKEN="fake-sa-token-0123456789"

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
fake="${work}/bin"
mkdir -p "${fake}"

# tailscale: `status --json` describes the state in ${FAKE_TS_STATE} (a file);
# "down" means no daemon to ask.
cat >"${fake}/tailscale" <<'EOF'
#!/usr/bin/env bash
[ "$*" = "status --json" ] || { echo "fake tailscale: unexpected args: $*" >&2; exit 2; }
state="$(cat "${FAKE_TS_STATE}")"
if [ "${state}" = down ]; then echo "failed to connect to local tailscaled" >&2; exit 1; fi
printf '{\n  "Version": "1.98.9",\n  "BackendState": "%s",\n' "${state}"
if [ -n "${FAKE_TS_HEALTH:-}" ]; then
  printf '  "Health": [\n    "%s"\n  ],\n' "${FAKE_TS_HEALTH}"
else
  printf '  "Health": null,\n'
fi
printf '  "CurrentTailnet": null\n}\n'
EOF
# kubectl: answers as ${FAKE_KUBECTL} says, and records each call.
cat >"${fake}/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"${FAKE_KUBECTL_CALLS}"
case "${FAKE_KUBECTL}" in
ok) echo '{"major": "1", "minor": "33"}' ;;
unauthorized) echo 'error: You must be logged in to the server (Unauthorized)' >&2; exit 1 ;;
unreachable)
  echo 'E1008 17:21:17.548509 2127 memcache.go:381] "Couldn'"'"'t get current server API group list"' >&2
  echo 'Unable to connect to the server: socks connect tcp 127.0.0.1:1055->k8s-api.lab.ipv1337.dev:6443: unknown error general SOCKS server failure' >&2
  exit 1 ;;
esac
EOF
# ssh present, so the hook does not try to apt-get it.
printf '#!/usr/bin/env bash\nexit 0\n' >"${fake}/ssh"
chmod +x "${fake}"/*

state_file="${work}/ts-state"
calls="${work}/kubectl-calls"

# run_hook <tailscale state> <kubectl answer> [VAR=value...]: sets out, err, rc.
run_hook() {
  local state="$1" answer="$2"
  shift 2
  printf '%s\n' "${state}" >"${state_file}"
  : >"${calls}"
  rm -rf "${work:?}/home" && mkdir -p "${work}/home"
  out="$(env -i HOME="${work}/home" PATH="${PATH_UNDER_TEST:-${fake}:/usr/bin:/bin}" \
    CLAUDE_CODE_REMOTE=true LAB_SA_TOKEN="${TOKEN}" TS_AUTHKEY=tskey-fake \
    FAKE_TS_STATE="${state_file}" FAKE_KUBECTL="${answer}" FAKE_KUBECTL_CALLS="${calls}" \
    "$@" bash "${HOOK}" 2>"${work}/err")"
  rc=$?
  err="$(cat "${work}/err")"
}

# verdict <label> <want: reachable|unreachable> [text the line must contain]
verdict() {
  local label="$1" want="$2" detail="${3:-}" line
  line="$(printf '%s\n' "${out}" | grep '^kube-setup: kubeconfig written' | tail -n1)"
  [ "${rc}" -eq 0 ] || fail "${label}: exit ${rc}, want 0 (a hook failure must never block the session)"
  case "${want}:${line}" in
  reachable:*"apiserver reachable via SOCKS5"*) ;;
  unreachable:*"apiserver is NOT reachable"*) ;;
  *) fail "${label}: want ${want}, stdout said: ${line:-<nothing>}"; return ;;
  esac
  if [ -n "${detail}" ] && [[ "${line}" != *"${detail}"* ]]; then
    fail "${label}: the line does not say '${detail}': ${line}"
    return
  fi
  case "${out}${err}" in *"${TOKEN}"*) fail "${label}: printed the ServiceAccount token"; return ;; esac
  pass "${label}"
}

echo "reports what is true"
run_hook Running ok
verdict "tailnet up, apiserver answers: reachable" reachable
if grep -q -- '--request-timeout' "${calls}" && grep -q 'get --raw=/version' "${calls}"; then
  pass "the probe is a bounded kubectl request"
else
  fail "unexpected probe: $(cat "${calls}")"
fi

run_hook NeedsLogin ok FAKE_TS_HEALTH="You are logged out. The last login error was: invalid key: API key does not exist"
verdict "revoked auth key: NOT reachable, with tailscaled's error" unreachable "invalid key: API key does not exist"
if [ -s "${calls}" ]; then fail "probed the apiserver with the tailnet logged out"; else pass "no apiserver probe while logged out"; fi

run_hook Stopped ok
verdict "tailnet stopped: NOT reachable" unreachable "the tailnet is Stopped"

run_hook down ok
verdict "no tailscaled: NOT reachable" unreachable "tailscaled is not running"
run_hook down ok TS_AUTHKEY=
verdict "no tailscaled and no auth key: says TS_AUTHKEY is not set" unreachable "TS_AUTHKEY is not set"

run_hook Running unauthorized
verdict "token rejected: NOT reachable, blames LAB_SA_TOKEN" unreachable "rejected LAB_SA_TOKEN"

run_hook Running unreachable
verdict "tailnet up, apiserver silent: NOT reachable, with kubectl's error" unreachable "general SOCKS server failure"

nots="${work}/no-tailscale"
mkdir -p "${nots}" && cp "${fake}/kubectl" "${fake}/ssh" "${nots}/"
if PATH=/usr/bin:/bin command -v tailscale >/dev/null 2>&1; then
  fail "cannot hide tailscale: it is in /usr/bin or /bin on this machine"
else
  PATH_UNDER_TEST="${nots}:/usr/bin:/bin" run_hook Running ok
  verdict "no tailscale binary: NOT reachable" unreachable "tailscale is not installed"
fi

echo "waits for a tailscale-up.sh that is still joining"
cat >"${work}/tailscale-up.sh" <<EOF
sleep 2
echo Running >"${state_file}"
EOF
printf 'NeedsLogin\n' >"${state_file}"
start=$SECONDS
(sleep 0.2; bash "${work}/tailscale-up.sh") &
joiner=$!
sleep 0.5
# run_hook rewrites the state file, so start the joiner's state by hand.
out="$(env -i HOME="${work}/home" PATH="${fake}:/usr/bin:/bin" CLAUDE_CODE_REMOTE=true \
  LAB_SA_TOKEN="${TOKEN}" TS_AUTHKEY=tskey-fake FAKE_TS_STATE="${state_file}" \
  FAKE_KUBECTL=ok FAKE_KUBECTL_CALLS="${calls}" bash "${HOOK}" 2>"${work}/err")"
rc=$?
err="$(cat "${work}/err")"
wait "${joiner}"
verdict "reports reachable once the join finishes" reachable
if [ $((SECONDS - start)) -lt 30 ]; then pass "and does not wait past it"; else fail "waited $((SECONDS - start))s"; fi

echo "wiring"
# settings.json runs .claude/session-start.sh, which runs this hook last
# (tools/ci/session-start_test.sh checks that wrapper's order).
wired="$(jq -r '.hooks.SessionStart[]?.hooks[]? | select(.type == "command") | .command' "${SETTINGS}" 2>/dev/null)"
# shellcheck disable=SC2016 # the wrapper's literal ${root}/<step> text
if [[ "${wired}" == *".claude/session-start.sh"* ]] && grep -qF '"${root}/.claude/kube-setup.sh"' "${ROOT}/.claude/session-start.sh"; then
  pass "the session-start hook runs it"
else
  fail "nothing runs it at session start: settings.json has '${wired}'"
fi
if [ -x "${HOOK}" ]; then pass "hook script is executable"; else fail "hook script is not executable"; fi

echo
if [ "${fails}" -gt 0 ]; then echo "${fails} check(s) FAILED" >&2; exit 1; fi
echo "all kube-setup checks passed"
