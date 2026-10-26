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

# Hermetic test for //tools/cloud-bootstrap:configure-tailscale and the
# Headscale / subnet-route behavior it configures in .claude/tailscale-up.sh:
#   1. configure-tailscale writes the expected .claude/tailscale-up.sh and
#      --check passes against the workspace's .claude/tailscale-up.sh;
#   2. A Headscale pre-auth key (non-tskey-* prefix) automatically passes
#      --login-server=https://headscale.ipv1337.dev and --accept-routes=true;
#   3. A commercial Tailscale key (tskey-*) with TS_LOGIN_SERVER unset omits
#      --login-server while still passing --accept-routes=true;
#   4. An explicit TS_LOGIN_SERVER overrides the login server regardless of key
#      prefix.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGURE="${HERE}/configure-tailscale.sh"

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() {
	printf '  ✗ %s\n' "$1" >&2
	fails=$((fails + 1))
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

hook="${work}/tailscale-up.sh"
printf '#!/usr/bin/env bash\n' >"$hook"

echo "configure-tailscale target"
if bash "$CONFIGURE" --file "$hook" >/dev/null && bash "$CONFIGURE" --check --file "$hook" >/dev/null; then
	pass "writes tailscale-up.sh and --check passes on the generated file"
else
	fail "configure-tailscale failed to write or check $hook"
fi

# Fake tailscaled + tailscale binaries to record `tailscale up` argv.
fake="${work}/bin"
mkdir -p "$fake"

cat >"${fake}/tailscaled" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"${fake}/tailscale" <<'EOF'
#!/usr/bin/env bash
case "$1" in
status)
	# First call checks if already connected (return 1); second call polls for
	# tailscaled socket readiness (return 0).
	count_file="${FAKE_TS_DIR}/status_count"
	c=0
	[ -f "$count_file" ] && c="$(cat "$count_file")"
	c=$((c + 1))
	echo "$c" >"$count_file"
	if [ "$c" -eq 1 ]; then
		exit 1
	fi
	exit 0
	;;
up)
	printf '%s\n' "$*" >"${FAKE_TS_DIR}/up_args"
	exit 0
	;;
ip)
	echo "100.64.0.99"
	exit 0
	;;
esac
exit 0
EOF

cat >"${fake}/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF

chmod +x "${fake}/tailscaled" "${fake}/tailscale" "${fake}/sudo"

run_up() {
	rm -rf "${work}/ts" "${work}/home"
	mkdir -p "${work}/ts" "${work}/home"
	env -i HOME="${work}/home" PATH="${fake}:/usr/bin:/bin" \
		CLAUDE_CODE_REMOTE=true FAKE_TS_DIR="${work}/ts" \
		"$@" bash "$hook" >/dev/null 2>&1
}

echo "headscale pre-auth key"
run_up TS_AUTHKEY="8fe9eb83c4488690525e34b543b548ce1fbbdcf57db11331"
up_args="$(cat "${work}/ts/up_args" 2>/dev/null || true)"
case "$up_args" in
*"--accept-routes=true"*) pass "passes --accept-routes=true" ;;
*) fail "missing --accept-routes=true in: $up_args" ;;
esac
case "$up_args" in
*"--login-server=https://headscale.ipv1337.dev"*) pass "selects https://headscale.ipv1337.dev for Headscale key" ;;
*) fail "missing Headscale --login-server in: $up_args" ;;
esac

echo "commercial tailscale key (tskey-*)"
run_up TS_AUTHKEY="tskey-auth-k123456CNTRL-abcdef"
up_args="$(cat "${work}/ts/up_args" 2>/dev/null || true)"
case "$up_args" in
*"--login-server="*) fail "unexpected --login-server for tskey-* when TS_LOGIN_SERVER is unset: $up_args" ;;
*) pass "omits --login-server for tskey-* when TS_LOGIN_SERVER is unset" ;;
esac

echo "explicit TS_LOGIN_SERVER override"
run_up TS_AUTHKEY="tskey-auth-k123456CNTRL-abcdef" TS_LOGIN_SERVER="https://custom.headscale.example"
up_args="$(cat "${work}/ts/up_args" 2>/dev/null || true)"
case "$up_args" in
*"--login-server=https://custom.headscale.example"*) pass "honors explicit TS_LOGIN_SERVER" ;;
*) fail "missing explicit TS_LOGIN_SERVER in: $up_args" ;;
esac

echo
if [ "$fails" -gt 0 ]; then
	echo "${fails} check(s) FAILED" >&2
	exit 1
fi
echo "all configure-tailscale checks passed"
