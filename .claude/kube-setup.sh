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

# Bootstrap kubectl access to the homelab k3s cluster from a Claude Code *cloud*
# session. Companion to tailscale-up.sh: that joins the tailnet using userspace
# networking and exposes a SOCKS5 proxy on localhost:1055; this installs kubectl
# (if absent) and writes a kubeconfig that dials the apiserver *through* that
# SOCKS5 proxy (cluster.proxy-url), so it works whether or not the sandbox has a
# TUN device.
#
# Best-effort by design: a setup hiccup must never block the Claude session, so
# every failure path exits 0 (mirrors tailscale-up.sh).
#
# SECRET HANDLING: the cluster-admin ServiceAccount token is deliberately NOT
# committed. Provide it as the LAB_SA_TOKEN environment variable in the Claude
# Code cloud environment settings. Fetch its value from a machine that already
# has cluster admin with:
#   kubectl -n claude-code get secret claude-code-token \
#     -o jsonpath='{.data.token}' | base64 -d
#
# The CA below is the cluster's public CA certificate (not a secret); it pins
# TLS to the k3s apiserver, whose serving cert carries k8s-api.lab.ipv1337.dev
# as a SAN (tls-san), so the HA failover name validates against any control
# plane that answers.
set -uo pipefail

# Cloud sessions only — no-op on a local checkout.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

# Use sudo for privileged moves only when not already root.
priv=()
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
	priv=(sudo)
fi

# Install kubectl if missing. Cached into the container snapshot after the first
# session, so subsequent sessions skip the download.
if ! command -v kubectl >/dev/null 2>&1; then
	ver="$(curl -fsSL https://dl.k8s.io/release/stable.txt 2>/dev/null || echo v1.31.0)"
	case "$(uname -m)" in
	x86_64) karch=amd64 ;;
	aarch64 | arm64) karch=arm64 ;;
	*) karch=amd64 ;;
	esac
	if curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${ver}/bin/linux/${karch}/kubectl"; then
		chmod +x /tmp/kubectl
		"${priv[@]}" mv /tmp/kubectl /usr/local/bin/kubectl
	else
		echo "kube-setup: kubectl download failed — skipping" >&2
		exit 0
	fi
fi

if [ -z "${LAB_SA_TOKEN:-}" ]; then
	echo "kube-setup: LAB_SA_TOKEN not set — add it to the cloud environment variables (see header)" >&2
	exit 0
fi

# Write the kubeconfig with restrictive perms.
mkdir -p "${HOME}/.kube"
(
	umask 077
	cat >"${HOME}/.kube/config" <<KUBECONFIG
apiVersion: v1
kind: Config
clusters:
  - name: lab
    cluster:
      server: https://k8s-api.lab.ipv1337.dev:6443
      certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJkekNDQVIyZ0F3SUJBZ0lCQURBS0JnZ3Foa2pPUFFRREFqQWpNU0V3SHdZRFZRUUREQmhyTTNNdGMyVnkKZG1WeUxXTmhRREUzTnpnek56a3dNakF3SGhjTk1qWXdOVEV3TURFeE1ESXdXaGNOTXpZd05UQTNNREV4TURJdwpXakFqTVNFd0h3WURWUVFEREJock0zTXRjMlZ5ZG1WeUxXTmhRREUzTnpnek56a3dNakF3V1RBVEJnY3Foa2pPClBRSUJCZ2dxaGtqT1BRTUJCd05DQUFRMGg0S21MeWtDd1F2dno0YWNKayt6UjRDSEhCRVZ1Z2pQbUcvMHprZHIKREliVERHSk5XR2xMZkVKMDlSWm9DUzVBWEVDZ3FvRDNzak9NVk1qWkFiWVdvMEl3UURBT0JnTlZIUThCQWY4RQpCQU1DQXFRd0R3WURWUjBUQVFIL0JBVXdBd0VCL3pBZEJnTlZIUTRFRmdRVUZTeXpxTjZvaHhmSHk1QnN3YUkxClVXOU5PQUV3Q2dZSUtvWkl6ajBFQXdJRFNBQXdSUUlnWWpIb3NKa0JlNmZHVTVjY2k5WlhkRWM1NGljMmUvOXEKMWZHVEhNQTJReHNDSVFERGpyYzRYREc2WVhOOGJIUE5aQjVPK2xuOUVnczJPK2g5L0xoa01JaW10Zz09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K
      proxy-url: socks5://localhost:1055
contexts:
  - name: lab
    context:
      cluster: lab
      user: claude-code
      namespace: default
current-context: lab
users:
  - name: claude-code
    user:
      token: ${LAB_SA_TOKEN}
KUBECONFIG
)
chmod 600 "${HOME}/.kube/config"

# Persist env for the session so kubectl + ad-hoc curl just work.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
	{
		echo "export KUBECONFIG=${HOME}/.kube/config"
		echo 'export NO_PROXY="100.64.0.0/10,k8s-api.lab.ipv1337.dev,.lab.ipv1337.dev,localhost,127.0.0.1"'
	} >>"$CLAUDE_ENV_FILE"
fi

echo "kube-setup: kubeconfig written (context 'lab'); apiserver reachable via SOCKS5 :1055"
exit 0
