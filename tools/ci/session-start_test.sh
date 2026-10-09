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

# Guard for .claude/session-start.sh, the SessionStart hook that runs
# cloud-bootstrap.sh, tailscale-up.sh and kube-setup.sh in that order. The later
# steps need what the earlier ones made (the tailscale binary, and the
# TS_AUTHKEY / LAB_SA_TOKEN cloud-bootstrap fetches into session.env), and
# Claude Code runs an event's hooks in parallel, so as three hooks they raced.
#
# Runs the real wrapper against fake steps that record when they start and end,
# and checks: one step finishes before the next starts; each step sees what the
# one before it wrote; a failing step does not stop the next; their stdout comes
# through in order; it always exits 0. Then checks the wiring: settings.json runs
# the wrapper, no SessionStart hook runs a step on its own (that would race
# again), and every step the wrapper names exists.

set -uo pipefail

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
WRAPPER="${ROOT}/.claude/session-start.sh"
SETTINGS="${ROOT}/.claude/settings.json"
STEPS=(tools/cloud-bootstrap/cloud-bootstrap.sh .claude/tailscale-up.sh .claude/kube-setup.sh)

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# A copy of the repo layout the wrapper resolves its steps against, with each
# step replaced by a fake. Each fake logs start/end; the first takes a moment and
# then writes session.env, the next two log whether they could see it.
tree="${work}/tree"
mkdir -p "${tree}/.claude" "${tree}/tools/cloud-bootstrap"
cp "${WRAPPER}" "${tree}/.claude/session-start.sh"
log="${work}/log"
env_file="${work}/session.env"

fake_step() { # <path> <name> <body>
  cat >"${tree}/$1" <<EOF
#!/usr/bin/env bash
echo "start $2" >>"${log}"
$3
echo "end $2" >>"${log}"
EOF
  chmod +x "${tree}/$1"
}
seen='if [ -s "'"${env_file}"'" ]; then echo "  saw session.env" >>"'"${log}"'"; fi'
fake_step tools/cloud-bootstrap/cloud-bootstrap.sh cloud-bootstrap \
  "sleep 1; echo TS_AUTHKEY=x >\"${env_file}\"; echo 'cloud-bootstrap: out'"
fake_step .claude/tailscale-up.sh tailscale-up "${seen}; echo 'tailscale-up: out'"
fake_step .claude/kube-setup.sh kube-setup "${seen}; echo 'kube-setup: out'"

echo "runs the steps in order"
out="$(cd / && bash "${tree}/.claude/session-start.sh")"
rc=$?
want="start cloud-bootstrap
end cloud-bootstrap
start tailscale-up
  saw session.env
end tailscale-up
start kube-setup
  saw session.env
end kube-setup"
if [ "$(cat "${log}")" = "${want}" ]; then
  pass "each step finishes before the next starts, and sees session.env"
else
  fail "steps overlapped or ran out of order:"$'\n'"$(cat "${log}")"
fi
if [ "${out}" = $'cloud-bootstrap: out\ntailscale-up: out\nkube-setup: out' ]; then
  pass "their stdout comes through, in order"
else
  fail "stdout: ${out}"
fi
if [ "${rc}" -eq 0 ]; then pass "exits 0"; else fail "exit ${rc}"; fi

echo "a failing step does not stop the rest"
: >"${log}"
rm -f "${env_file}"
fake_step .claude/tailscale-up.sh tailscale-up "exit 3"
bash "${tree}/.claude/session-start.sh" >/dev/null
rc=$?
if grep -qx "end kube-setup" "${log}"; then pass "kube-setup.sh still runs"; else fail "stopped after a failing step: $(cat "${log}")"; fi
if [ "${rc}" -eq 0 ]; then pass "and the hook still exits 0"; else fail "exit ${rc}"; fi

echo "wiring"
hooks="$(jq -r '.hooks.SessionStart[]?.hooks[]? | select(.type == "command") | .command' "${SETTINGS}" 2>/dev/null)"
case "${hooks}" in
*".claude/session-start.sh"*) pass "settings.json runs .claude/session-start.sh at session start" ;;
*) fail "settings.json does not run .claude/session-start.sh: '${hooks}'" ;;
esac
for step in "${STEPS[@]}"; do
  case "${hooks}" in
  *"${step}"*) fail "settings.json runs ${step} as its own hook, which races the others" ;;
  *) pass "${step} is not a hook of its own" ;;
  esac
  if grep -qF "\"\${root}/${step}\"" "${WRAPPER}" && [ -x "${ROOT}/${step}" ]; then
    pass "the wrapper runs ${step}, which exists"
  else
    fail "the wrapper does not run ${step}, or it is missing or not executable"
  fi
done
# shellcheck disable=SC2016 # the wrapper's literal ${root}/<step> text
order="$(grep -oE '"\$\{root\}/[^"]+"' "${WRAPPER}" | tr -d '"' | sed 's|^\${root}/||' | paste -sd ' ')"
if [ "${order}" = "${STEPS[*]}" ]; then pass "in the order: ${order}"; else fail "wrapper order is '${order}', want '${STEPS[*]}'"; fi
if [ -x "${WRAPPER}" ]; then pass "wrapper is executable"; else fail "wrapper is not executable"; fi

echo
if [ "${fails}" -gt 0 ]; then echo "${fails} check(s) FAILED" >&2; exit 1; fi
echo "all session-start checks passed"
