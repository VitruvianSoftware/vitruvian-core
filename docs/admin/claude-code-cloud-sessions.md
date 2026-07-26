# Homelab access from Claude Code cloud sessions

**Tool-specific setup — not part of the repo's agent contract.** The repo-wide agent
guide is the vendor-neutral [`AGENTS.md`](../../AGENTS.md); this page holds the
Claude-Code-specific wiring that only applies to cloud sessions of that tool, so
AGENTS.md stays usable by any agent (Antigravity/Gemini, Copilot, Cursor, opencode, …).

If you are running a different tool, none of this applies — you need your own transport
to the tailnet, and the facts that generalise are: the cluster API is the HA name
`k8s-api.lab.ipv1337.dev:6443`, and node access is by SSH key as user `james`.

## Kubernetes access
Cloud sessions can drive the homelab k3s cluster with `kubectl` over Tailscale.
Two `SessionStart` hooks wire this up automatically (registered in
`.claude/settings.json`):
- `.claude/tailscale-up.sh` — joins the tailnet (userspace networking; exposes a
  SOCKS5 proxy on `localhost:1055`, since the sandbox has no TUN device).
- `.claude/kube-setup.sh` — installs `kubectl` and writes `~/.kube/config`
  (context `lab`) pointed at `https://k8s-api.lab.ipv1337.dev:6443`, dialing the
  apiserver through that SOCKS5 proxy.

Verify with `kubectl get nodes` (context `lab`). If it works, you're done.

**Prerequisites (set once, outside this repo):**
- Env vars on the cloud environment: `TS_AUTHKEY` (reusable, pre-authorized for
  `tag:claude-cloud`) and `LAB_SA_TOKEN` (the **non-expiring** ServiceAccount
  token — `kubectl -n claude-code get secret claude-code-token -o
  jsonpath='{.data.token}' | base64 -d`, *not* `kubectl create token`, which
  expires).
- Tailnet policy: `tag:claude-cloud` must have an ACL grant to the control-plane
  nodes on `6443`, or the node joins able to *see* the netmap but not *touch* it
  (every TCP connection is silently dropped).

**Troubleshooting:**
- `unsupported scheme "socks5h"` → kubeconfig must use `proxy-url: socks5://`
  (kubectl/client-go reject `socks5h`; only `curl` accepts it).
- `Unauthorized` (401) → `LAB_SA_TOKEN` is wrong/expired; transport is fine.
- `i/o timeout` / connection refused to `100.x` → tailnet ACL is not granting
  `tag:claude-cloud`, or `tailscaled`/the SOCKS5 proxy isn't running.
- The cluster API is the HA name `k8s-api.lab.ipv1337.dev` (Cloudflare A record →
  the 3 control-plane tailnet IPs); the apiserver serving cert carries it as a
  `tls-san`, so TLS validates against whichever control plane answers.

## SSH access
A cloud session has **passwordless SSH into every homelab node** — use it to
configure or troubleshoot a node directly when needed. Auth is a dedicated agent
**key**, NOT Tailscale SSH: Tailscale SSH is *not* enabled on these hosts, so
`tailscale ssh` falls back to regular ssh and fails on host keys — use the key
path below.

Wiring (automatic via the merged `SessionStart` hooks):
- `kube-setup.sh` installs the private key from the `CLAUDE_SSH_KEY` env var into
  `~/.ssh/id_ed25519` each session, regenerates `id_ed25519.pub` from it, and writes
  `~/.ssh/config` (`StrictHostKeyChecking accept-new`, `GSSAPIAuthentication no`).
  It also installs `openssh-client`.
- The matching public key is in `~/.ssh/authorized_keys` for user **`james`** on each host.

Userspace networking means there's no kernel route to `100.x`, so ssh must dial
through the SOCKS5 proxy `tailscale-up.sh` exposes on `localhost:1055` (needs
`netcat-openbsd`):

```bash
ssh -o ProxyCommand='nc -X 5 -x localhost:1055 %h %p' james@<tailnet-ip> '<cmd>'
```

Nodes (k3s cluster; run `tailscale status` for live IPs): `fedora` control-plane,
`nuc9i5` + `nuc9i9` workers, and the macOS nodes (`james-macbook-pro`, …).

If it breaks (the hooks normally prevent these):
- `Permission denied (publickey)` with a correct private key → a stale `.pub` is
  advertising the wrong key: `ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub`.
- `Connection closed` over the proxy → ssh tried GSSAPI first; add
  `-o GSSAPIAuthentication=no -o PreferredAuthentications=publickey`.
- missing tools → `apt-get install -y openssh-client netcat-openbsd`.

Rotate by regenerating the pair and updating `CLAUDE_SSH_KEY` + each `authorized_keys`.

