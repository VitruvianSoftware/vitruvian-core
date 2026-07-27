# Homelab access from Claude Code cloud sessions

**Tool-specific setup — not part of the repo's agent contract.** The repo-wide agent
guide is the vendor-neutral [`AGENTS.md`](../../AGENTS.md); this page holds the
Claude-Code-specific wiring that only applies to cloud sessions of that tool, so
AGENTS.md stays usable by any agent (Antigravity/Gemini, Copilot, Cursor, opencode, …).

If you are running a different tool, none of this applies — you need your own transport
to the tailnet, and the facts that generalise are: the cluster API is the HA name
`k8s-api.lab.ipv1337.dev:6443`, and node access is by SSH key as user `james`.

## Tooling and credentials: the profile

A cloud session boots a bare Ubuntu box — `git`, `go`, `node`, `docker`, and none
of this repo's CLI tooling or credentials. The first `SessionStart` hook,
[`//tools/cloud-bootstrap`](../../tools/cloud-bootstrap/README.md), fixes both.

Two variables on the cloud environment drive it:

| variable | what it is |
| --- | --- |
| `VITRUVIAN_PROFILE` | which profile this environment is. **Use `all`** unless you specifically want a narrower session (`core`, `infra`, `homelab`, `readonly`) |
| `VITRUVIAN_CLOUD_KEY` | that profile's GCP service-account key — the **only** credential on the environment |

The profile is the blast-radius boundary. Its row in
[`tools/cloud-bootstrap/profiles.tsv`](../../tools/cloud-bootstrap/profiles.tsv)
decides which CLIs are installed and which secrets the session may hold; a `core`
session cannot obtain a Pulumi token or a cluster credential, because its row does
not name them and its service account has no IAM to read them.

Everything beyond that one key comes from Secret Manager at session start, so a
GitHub PAT, Pulumi token, Tailscale auth key or cluster token rotates **without
editing the cloud environment at all**. The key's `client_email` must match the
account its profile declares — a mismatched key is refused and fails closed.

`all` is one service account holding every credential the agent needs — that is
the everyday configuration, and it is just the two variables above. The narrower
rows exist for when you deliberately want a session that *cannot* reach
production, e.g. one reviewing third-party code; such a session **blanks** every
manifest-named credential it does not claim, rather than merely declining to add
one (a smaller blast radius, not a sandbox). Profiles can also be combined
(`core,homelab`), but prefer a single row: combining keeps each profile's
identity separate and therefore needs a key each, which is only worth it to hold
two existing boundaries at once.

The *Setup script* field should run the bootstrap's **install** phase, so the
tools are baked into the cached environment image rather than re-downloaded each
session (`tailscale` included — it is a profile decision now, not a hard-coded
install line):

```bash
#!/bin/bash
S=/home/user/vitruvian-core/tools/cloud-bootstrap/cloud-bootstrap.sh
[ -x "$S" ] && exec "$S" install --force
echo "cloud-bootstrap: repo not cloned yet — the SessionStart hook will install instead"
```

`--force` is required: `CLAUDE_CODE_REMOTE` is not set that early, so without it
the script silently no-ops. Credentials are deliberately *not* done here — the
`SessionStart` hook establishes those per session, so no token is baked into a
cached image.

Verify from inside a session — you cannot shell into a cloud session, so ask the
agent to run this and report back:

```sh
bazel run //tools/cloud-bootstrap:whoami     # tools, identity, credentials (no values)
```

It prints each credential by name and byte length, never its value, which is
enough to tell a real token from the sandbox's short placeholders.

The full rationale — why token-based, why one credential, why not keyless, where
things land on disk — is in the
[tool's README](../../tools/cloud-bootstrap/README.md).

> The `TS_AUTHKEY` and `LAB_SA_TOKEN` variables described below still work exactly
> as they always have: a value already set on the environment wins, and
> cloud-bootstrap leaves it alone. Moving them into the `homelab` profile's Secret
> Manager entries is the upgrade, not a requirement.

## Build cache

The `auth` phase also points a plain `bazel` at the shared BuildBuddy cache, for
any profile that both installs `bazel` and declares `BUILDBUDDY_API_KEY`.

It has to, because the config that enables the cache lives in `user.bazelrc` —
which is **git-ignored**, so a freshly cloned sandbox has none. Without this a
session cold-builds a large polyglot repo on a 4-core box while holding a
perfectly good key it never uses. A developer gets this from `bazel run
//tools/remote:setup`; a cloud session has nobody to run it, so the bootstrap
runs it for them (delegating to that same script, so the block has one
definition).

Two properties worth knowing:

- **Cache only — never RBE.** Full `--config=remote` sets
  `--remote_download_outputs=minimal` and cannot run macOS targets, so as a
  default it would break `bazel run` of local tools and any lane consuming
  `bazel-bin`. RBE stays an explicit opt-in, exactly as on a laptop.
- **It happens in `auth`, never `install`.** The block contains the API key, and
  `install` is what the *Setup script* bakes into a cached image. Writing it
  there would bake a credential into a snapshot.

> **A wrong key fails silently.** Bazel treats remote-cache auth errors as
> warnings and builds locally, so the session just gets slow — and because the
> BES upload is async, the giveaway surfaces on the *next* invocation:
> ```
> WARNING: Remote Cache: UNAUTHENTICATED: Invalid API key "0***J"
> ```
> `:whoami` reports the cache as *configured*, which is all it can check without
> a network round trip — length alone cannot tell a valid 20-byte key from an
> invalid one. **If builds are slow, read the warnings before trusting that
> line.** Rotate with [`//tools/rotate-buildbuddy-key`](../../tools/rotate-buildbuddy-key).

## GCP access

A cloud session can run `bazel run //infrastructure/pulumi/<project>:{preview,up}`
and ad-hoc `gcloud` — with **no GCP credential on the cloud environment at all**.

It cannot have one: `iam.disableServiceAccountKeyCreation` is enforced org-wide
(`gcp-org/envs/shared/org_policy.go`, "prevent SA key sprawl"), so there is no
service-account key to hand a sandbox. Instead
[`//tools/gcp-token`](../../tools/gcp-token/README.md) mints a short-lived token
**over the tailnet** from a homelab node that is already `gcloud auth login`-ed.
The refresh token never leaves that node; the session holds a ~1h access token.
Tailnet membership is the authentication factor — drop the node from the tailnet
or revoke the agent SSH key and cloud sessions lose GCP immediately.

`//tools/pulumi` calls it automatically, so the wrappers work unchanged. Local
credentials always win, so a laptop and CI take the same code path and never
touch the network.

**Prerequisite (once per node):** install the Google Cloud SDK and run
`gcloud auth login <account>`, where `<account>` is what
`infrastructure/gcp-identities.tsv` pins for the work in question. Brokers are a
LIST tried in order (`VITRUVIAN_GCP_BROKERS`, default
always-on nodes first, then laptops), with the winner cached; set up more than
one so a sleeping or lapsed node is not a single point of failure.

**Workspace logins lapse per node.** Google Cloud session control expires a
managed account's gcloud login periodically and wants an interactive re-login ssh
cannot give it. This is per NODE, not per account: measured on the real fleet at
the same moment, `james-macbook-pro` had lapsed for
`james@vitruviansoftware.dev` while `james-mbp16` minted it fine. Failover routes
around the lapsed node automatically — which is the main reason brokers are a
list. Re-login on a lapsed node whenever convenient, or widen **Admin console →
Security → Access and data control → Google Cloud session control** to make it
rarer. The failure names itself (`REAUTH LAPSED`).

## Kubernetes access
Cloud sessions can drive the homelab k3s cluster with `kubectl` over Tailscale.
Two `SessionStart` hooks wire this up automatically (registered in
`.claude/settings.json`):
- `.claude/tailscale-up.sh` — joins the tailnet (userspace networking; exposes a
  SOCKS5 proxy on `localhost:1055`, since the sandbox has no TUN device). The
  binary itself comes from `//tools/cloud-bootstrap`; this hook only (re)starts
  the daemon, which the environment cache cannot snapshot.
- `.claude/kube-setup.sh` — installs `kubectl` and writes `~/.kube/config`
  (context `lab`) pointed at `https://k8s-api.lab.ipv1337.dev:6443`, dialing the
  apiserver through that SOCKS5 proxy.

Verify with `kubectl get nodes` (context `lab`). If it works, you're done.

**Prerequisites (set once, outside this repo):**
- Env vars on the cloud environment (or, better, the `homelab` profile's Secret
  Manager entries — same values, rotated without touching the environment):
  `TS_AUTHKEY` (reusable, and permitting **untagged** device registration — see
  below) and `LAB_SA_TOKEN` (the **non-expiring** ServiceAccount
  token — `kubectl -n claude-code get secret claude-code-token -o
  jsonpath='{.data.token}' | base64 -d`, *not* `kubectl create token`, which
  expires).
- Tailnet policy: **nothing to configure while the node joins untagged.**
  `tailscale-up.sh` passes `--accept-routes=false` and no `--advertise-tags`, so
  the node registers as a personal device of the tailnet owner and inherits that
  account's access to its own machines. `tailscale status` shows it owned by
  `james.nguyen@`, not tagged.

> **Do not "fix" this by tagging the key.** A tagged node is owned by the *tag*,
> not the user, and inherits none of that access — so `tag:claude-cloud` would
> then need an explicit ACL grant to the control planes on `6443`, or the session
> joins able to *see* the netmap but not *touch* it (every TCP connection
> silently dropped, which presents as `i/o timeout`, not as a permission error).
> This matters most if you regenerate `TS_AUTHKEY` as an **ephemeral** key so
> finished sessions stop leaving stale nodes behind — that is worth doing, but
> issue it untagged, or add the ACL grant in the same change.

**Troubleshooting:**
- `unsupported scheme "socks5h"` → kubeconfig must use `proxy-url: socks5://`
  (kubectl/client-go reject `socks5h`; only `curl` accepts it).
- `Unauthorized` (401) → `LAB_SA_TOKEN` is wrong/expired; transport is fine.
- `i/o timeout` / connection refused to `100.x` → `tailscaled`/the SOCKS5 proxy
  isn't running, or the node joined **tagged** and so lost the owner's ambient
  access (check `tailscale status`: it should show the node owned by the tailnet
  owner, not by a tag). A tagged node needs an explicit ACL grant to the control
  planes on `6443`.
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

