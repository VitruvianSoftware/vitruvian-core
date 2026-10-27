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

# Sanctioned Bazel target (`bazel run //tools/cloud-bootstrap:configure-tailscale`)
# to configure `.claude/tailscale-up.sh` for the self-hosted Headscale control
# plane (`https://headscale.ipv1337.dev`) and subnet-routed homelab access
# (`--accept-routes=true`).
#
# Usage:
#   bazel run //tools/cloud-bootstrap:configure-tailscale
#   bazel run //tools/cloud-bootstrap:configure-tailscale -- --check
#   bazel run //tools/cloud-bootstrap:configure-tailscale -- --file <path>

set -euo pipefail

mode="write"
target_file=""

while [ $# -gt 0 ]; do
	case "$1" in
	--check)
		mode="check"
		shift
		;;
	--file)
		target_file="$2"
		shift 2
		;;
	*)
		echo "configure-tailscale: unknown argument: $1" >&2
		exit 2
		;;
	esac
done

if [ -z "$target_file" ]; then
	root="${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel)}"
	target_file="${root}/.claude/tailscale-up.sh"
fi

if [ ! -f "$target_file" ]; then
	echo "configure-tailscale: target file not found: $target_file" >&2
	exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

cat >"$tmp" <<'EOF'
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

# Join this Claude Code *cloud* sandbox to the tailnet so a web/mobile session
# can reach tailnet-only devices (homelab boxes, internal services).
#
# Best-effort by design: a Tailscale hiccup must never block the Claude session,
# so every failure path exits 0 (mirrors devx-tailscale-up.service).
#
# Why a SessionStart hook and not the cloud "Setup script": the cloud
# environment cache snapshots files, not running processes, so a daemon started
# in the Setup script would not be running on cached/resumed sessions. The
# BINARY is installed by //tools/cloud-bootstrap, which .claude/session-start.sh
# runs to completion before this, for any profile whose `tools` column lists
# tailscale; this hook (re)starts the daemon each session.
#
# Why userspace networking: the sandbox has no TUN device and all egress is
# forced through an HTTP/HTTPS proxy, so raw WireGuard cannot leave. tailscaled
# dials control + DERP through $HTTPS_PROXY and exposes a local SOCKS5/HTTP proxy
# on :1055 for reaching peers. Connectivity is DERP-relayed, not direct.
#
# Reach peers once up:  curl --proxy socks5h://localhost:1055 http://<peer>/
set -uo pipefail

# Cloud sessions only — no-op on a local checkout.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

# Pick up anything //tools/cloud-bootstrap resolved for this session's profile.
# Hooks are separate processes, so a TS_AUTHKEY it fetched from Secret Manager is
# NOT in this one's environment — without this, the `homelab` profile's whole
# point (rotate the auth key in one place, no cloud-environment edit) would not
# reach tailscaled. A TS_AUTHKEY set directly on the environment still works
# unchanged; cloud-bootstrap leaves those alone.
_session_env="$HOME/.config/vitruvian-core/cloud/session.env"
# shellcheck disable=SC1090 # path is fixed; the file is 0600 and machine-written
[ -f "$_session_env" ] && . "$_session_env"

if ! command -v tailscale >/dev/null 2>&1; then
	echo "tailscale-up: binary missing — this session's \$VITRUVIAN_PROFILE does not list" >&2
	echo "  tailscale (see tools/cloud-bootstrap/profiles.tsv); add it, or use a profile that does" >&2
	exit 0
fi

# Use sudo for privileged commands only when we are not already root.
priv=()
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
	priv=(sudo)
fi

# Already connected (e.g. a resumed session reusing the same VM)? Nothing to do.
if "${priv[@]}" tailscale status >/dev/null 2>&1; then
	echo "tailscale-up: already connected"
	exit 0
fi

if [ -z "${TS_AUTHKEY:-}" ]; then
	echo "tailscale-up: TS_AUTHKEY not set — add it to the cloud environment variables" >&2
	exit 0
fi

# Userspace networking + dial out via the sandbox proxy; expose SOCKS5/HTTP on :1055.
tailscaled_args=(
	--tun=userspace-networking
	--socks5-server=localhost:1055
	--outbound-http-proxy-listen=localhost:1055
	--statedir=/var/lib/tailscale
)
"${priv[@]}" tailscaled "${tailscaled_args[@]}" >/tmp/tailscaled.log 2>&1 &

# tailscaled reports ready a beat after its socket appears; poll briefly.
for _ in $(seq 1 20); do
	"${priv[@]}" tailscale status >/dev/null 2>&1 && break
	sleep 0.5
done

# --accept-routes=true: allow userspace SOCKS5 (:1055) to reach homelab LAN
# routes (192.168.86.0/24, including k8s-api.lab.ipv1337.dev -> 192.168.86.64)
# advertised by homelab-subnet-router. The node joins untagged (a personal
# device) so it inherits the owner's access to their own devices.
# TS_AUTHKEY must be reusable and permit untagged device registration.
up_args=(
	--authkey="${TS_AUTHKEY}"
	--hostname="claude-cloud-$(hostname -s 2>/dev/null || echo sandbox)"
	--accept-routes=true
	--timeout=30s
)
if [ -n "${TS_LOGIN_SERVER:-}" ]; then
	up_args+=(--login-server="${TS_LOGIN_SERVER}")
elif [[ "${TS_AUTHKEY}" != tskey-* ]]; then
	up_args+=(--login-server="https://headscale.ipv1337.dev")
fi
if ! "${priv[@]}" tailscale up "${up_args[@]}"; then
	echo "tailscale-up: 'tailscale up' failed — see /tmp/tailscaled.log" >&2
	exit 0
fi

echo "tailscale-up: connected as $("${priv[@]}" tailscale ip -4 2>/dev/null | head -n1)"
echo "tailscale-up: reach peers via  curl --proxy socks5h://localhost:1055 http://<peer>/"
exit 0
EOF

if [ "$mode" = "check" ]; then
	if ! diff -u "$target_file" "$tmp"; then
		echo "configure-tailscale: $target_file is out of sync; run 'bazel run //tools/cloud-bootstrap:configure-tailscale'" >&2
		exit 1
	fi
	echo "configure-tailscale: $target_file is up to date"
	exit 0
fi

cp "$tmp" "$target_file"
chmod +x "$target_file"
echo "configure-tailscale: updated $target_file"
