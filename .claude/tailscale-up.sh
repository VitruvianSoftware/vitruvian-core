#!/usr/bin/env bash
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

"${priv[@]}" tailscaled \
  --tun=userspace-networking \
  --socks5-server=localhost:1055 \
  --outbound-http-proxy-listen=localhost:1055 \
  --statedir=/var/lib/tailscale \
  >/tmp/tailscaled.log 2>&1 &

# tailscaled reports ready a beat after its socket appears; poll briefly.
for _ in $(seq 1 20); do
  "${priv[@]}" tailscale status >/dev/null 2>&1 && break
  sleep 0.5
done

# --accept-routes=false: scope is tailnet devices only, not subnets behind a
# router. Key must be ephemeral + pre-authorized for tag:claude-cloud.
if ! "${priv[@]}" tailscale up \
  --authkey="${TS_AUTHKEY}" \
  --hostname="claude-cloud-$(hostname -s 2>/dev/null || echo sandbox)" \
  --advertise-tags=tag:claude-cloud \
  --accept-routes=false \
  --timeout=30s; then
  echo "tailscale-up: 'tailscale up' failed — see /tmp/tailscaled.log" >&2
  exit 0
fi

echo "tailscale-up: connected as $("${priv[@]}" tailscale ip -4 2>/dev/null | head -n1)"
echo "tailscale-up: reach peers via  curl --proxy socks5h://localhost:1055 http://<peer>/"
exit 0
