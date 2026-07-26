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
# in the Setup script would not be running on cached/resumed sessions. The Setup
# script only installs the binary; this hook (re)starts the daemon each session.
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
	echo "tailscale-up: binary missing — add the install line to the cloud env Setup script" >&2
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

# --accept-routes=false: scope is tailnet devices only, not subnets behind a
# router. The node joins untagged (a personal device) so it inherits the
# owner's access to their own devices — no tailnet ACL grant required.
# TS_AUTHKEY must be reusable and permit untagged device registration.
up_args=(
	--authkey="${TS_AUTHKEY}"
	--hostname="claude-cloud-$(hostname -s 2>/dev/null || echo sandbox)"
	--accept-routes=false
	--timeout=30s
)
if ! "${priv[@]}" tailscale up "${up_args[@]}"; then
	echo "tailscale-up: 'tailscale up' failed — see /tmp/tailscaled.log" >&2
	exit 0
fi

echo "tailscale-up: connected as $("${priv[@]}" tailscale ip -4 2>/dev/null | head -n1)"
echo "tailscale-up: reach peers via  curl --proxy socks5h://localhost:1055 http://<peer>/"
exit 0
